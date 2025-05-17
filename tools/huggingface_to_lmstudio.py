#!/usr/bin/env python3
"""
Hugging Face to LM Studio Converter

This script converts Hugging Face's blob-based model structure to LM Studio's flat structure
using symbolic links rather than duplicating files. It can process a single model or batch
process all models in the Hugging Face cache directory.
"""

import os
import argparse
import json
import re
import shutil
from pathlib import Path


def resolve_symlink(link_path):
    """Resolve a symbolic link to its target file path"""
    if os.path.islink(link_path):
        target = os.readlink(link_path)
        # If target is relative, make it absolute based on link directory
        if not os.path.isabs(target):
            link_dir = os.path.dirname(link_path)
            target = os.path.normpath(os.path.join(link_dir, target))
        return target
    return link_path


def find_latest_snapshot(hf_dir):
    """Find the latest snapshot in the Hugging Face model directory"""
    snapshots_dir = os.path.join(hf_dir, "snapshots")

    if not os.path.exists(snapshots_dir):
        return None

    # List all snapshots and sort by modification time (newest first)
    snapshots = [
        os.path.join(snapshots_dir, d)
        for d in os.listdir(snapshots_dir)
        if os.path.isdir(os.path.join(snapshots_dir, d)) and not d.startswith(".")
    ]

    if not snapshots:
        return None

    # Sort by modification time (newest first)
    snapshots.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    return snapshots[0]


def find_model_files(hf_dir):
    """Find and categorize all model files in the Hugging Face directory"""
    model_files = {}

    # First check if we have a snapshots directory
    snapshot_dir = find_latest_snapshot(hf_dir)

    # If we have a snapshot, use it as our primary source of files
    if snapshot_dir:
        print(f"Using latest snapshot: {os.path.basename(snapshot_dir)}")
        source_dir = snapshot_dir
    else:
        # Otherwise, use the root directory
        source_dir = hf_dir

    # Walk through all files in the source directory
    for item in os.listdir(source_dir):
        item_path = os.path.join(source_dir, item)

        # Check if it's a model weight file or config file
        if (
            item.endswith(".bin")
            or item.endswith(".safetensors")
            or item
            in (
                "config.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "vocab.json",
                "merges.txt",
                "special_tokens_map.json",
                "added_tokens.json",
                "model.safetensors.index.json",
            )
        ):

            # Resolve symlink if file is a symbolic link
            target_path = resolve_symlink(item_path)
            model_files[item] = target_path

    return model_files


def extract_shard_info(filename):
    """Extract shard number and total shards from a filename like 'model-00001-of-00002.safetensors'"""
    match = re.search(r"model-(\d+)-of-(\d+)", filename)
    if match:
        shard_num = int(match.group(1))
        total_shards = int(match.group(2))
        return shard_num, total_shards
    return None, None


def create_lmstudio_structure(hf_dir, lm_studio_dir, use_symlinks=True):
    """Create LM Studio flat structure from Hugging Face directory"""
    # Create output directory if it doesn't exist
    os.makedirs(lm_studio_dir, exist_ok=True)

    # Find all model files
    model_files = find_model_files(hf_dir)

    # Dictionary to track model weight files and their shard info
    weight_files = {}

    # Process each file
    for filename, full_path in model_files.items():
        # Special handling for weight files
        if filename.endswith(".bin") or filename.endswith(".safetensors"):
            # Check if it's a sharded file (like model-00001-of-00005.safetensors)
            shard_num, total_shards = extract_shard_info(filename)

            if shard_num is not None:
                # For sharded files
                destination = os.path.join(lm_studio_dir, filename)
                weight_files[shard_num] = {
                    "source": full_path,
                    "destination": destination,
                    "total_shards": total_shards,
                }
            else:
                # For non-sharded weight files
                destination = os.path.join(lm_studio_dir, filename)

                if use_symlinks:
                    # Create symbolic link
                    if os.path.exists(destination):
                        os.unlink(destination)
                    os.symlink(os.path.abspath(full_path), destination)
                    print(f"Created symlink: {destination} -> {full_path}")
                else:
                    # Copy the file
                    shutil.copy2(full_path, destination)
                    print(f"Copied: {full_path} -> {destination}")

        else:
            # For configuration and tokenizer files
            destination = os.path.join(lm_studio_dir, filename)

            if use_symlinks:
                # Create symbolic link
                if os.path.exists(destination):
                    os.unlink(destination)
                os.symlink(os.path.abspath(full_path), destination)
                print(f"Created symlink: {destination} -> {full_path}")
            else:
                # Copy the file
                shutil.copy2(full_path, destination)
                print(f"Copied: {full_path} -> {destination}")

    # Create proper links for sharded weight files
    if weight_files:
        # Sort by shard number
        shards = sorted(weight_files.items())
        total_shards = shards[0][1]["total_shards"]

        # Create metadata file for LM Studio if needed
        metadata = {"total_shards": total_shards}

        metadata_path = os.path.join(lm_studio_dir, "lm-metadata.json")
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)
        print(f"Created metadata file: {metadata_path}")

        # Create symlinks or copy files
        for shard_num, info in shards:
            if use_symlinks:
                if os.path.exists(info["destination"]):
                    os.unlink(info["destination"])
                os.symlink(os.path.abspath(info["source"]), info["destination"])
                print(f"Created symlink: {info['destination']} -> {info['source']}")
            else:
                shutil.copy2(info["source"], info["destination"])
                print(f"Copied: {info['source']} -> {info['destination']}")


def find_hf_models(base_dir):
    """Find all potential Hugging Face model directories in the cache"""
    potential_models = []

    # Handle path with ~ for home directory
    base_dir = os.path.expanduser(base_dir)

    if not os.path.isdir(base_dir):
        print(f"Error: Base directory '{base_dir}' does not exist.")
        return potential_models

    # Look for directories that could be models
    for item in os.listdir(base_dir):
        item_path = os.path.join(base_dir, item)

        if not os.path.isdir(item_path):
            continue

        # Check if directory looks like a HF model (has blobs or snapshots or config.json)
        if (
            item.startswith("models--")
            or os.path.isdir(os.path.join(item_path, "blobs"))
            or os.path.isdir(os.path.join(item_path, "snapshots"))
            or os.path.exists(os.path.join(item_path, "config.json"))
        ):
            potential_models.append(item_path)

    return potential_models


def process_model(hf_model_path, output_base_dir, use_symlinks=True):
    """Process a single model"""
    # Extract model name from path
    model_name = os.path.basename(hf_model_path)

    # Create output directory
    if model_name.startswith("models--"):
        # Convert "models--org--model-name" to "model-name"
        parts = model_name.split("--")
        if len(parts) >= 3:
            # Use just the model part (the last part)
            clean_name = parts[-1]
        else:
            clean_name = model_name
    else:
        clean_name = model_name

    output_dir = os.path.join(output_base_dir, clean_name)

    print(f"\nProcessing model: {model_name}")
    print(f"Output directory: {output_dir}")

    # Create LM Studio structure
    create_lmstudio_structure(hf_model_path, output_dir, use_symlinks=use_symlinks)

    return output_dir


def main():
    parser = argparse.ArgumentParser(
        description="Convert Hugging Face model structure to LM Studio format"
    )
    parser.add_argument(
        "--hf-dir", type=str, help="Path to specific Hugging Face model directory"
    )
    parser.add_argument(
        "--lm-studio-dir", type=str, help="Path to specific LM Studio output directory"
    )
    parser.add_argument(
        "--copy", action="store_true", help="Copy files instead of creating symlinks"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process all models in the Hugging Face cache",
    )
    parser.add_argument(
        "--cache-dir",
        type=str,
        default="~/.cache/huggingface/hub",
        help="Path to Hugging Face cache directory (default: ~/.cache/huggingface/hub)",
    )
    parser.add_argument(
        "--output-base",
        type=str,
        help="Base directory for LM Studio models when using --all",
    )
    parser.add_argument(
        "--model-filter",
        type=str,
        help="String filter to process only certain models when using --all",
    )

    args = parser.parse_args()

    # Check command arguments consistency
    if args.all:
        if args.hf_dir or args.lm_studio_dir:
            print("Warning: When using --all, --hf-dir and --lm-studio-dir are ignored")

        if not args.output_base:
            print("Error: When using --all, --output-base must be specified")
            return 1

        # Process all models in cache
        cache_dir = os.path.expanduser(args.cache_dir)
        if not os.path.isdir(cache_dir):
            print(f"Error: Cache directory '{cache_dir}' does not exist.")
            return 1

        print(f"Searching for models in {cache_dir}...")
        models = find_hf_models(cache_dir)

        if args.model_filter:
            # Filter models by name
            filtered_models = [m for m in models if args.model_filter in m]
            print(
                f"Found {len(filtered_models)} models matching filter '{args.model_filter}' (out of {len(models)} total models)"
            )
            models = filtered_models
        else:
            print(f"Found {len(models)} models")

        if not models:
            print("No models found to process.")
            return 0

        # Create output base directory
        os.makedirs(os.path.expanduser(args.output_base), exist_ok=True)

        # Process each model
        processed_models = []
        for model_path in models:
            try:
                output_dir = process_model(
                    model_path,
                    os.path.expanduser(args.output_base),
                    use_symlinks=not args.copy,
                )
                processed_models.append((model_path, output_dir))
                print(f"Successfully processed: {os.path.basename(model_path)}")
            except Exception as e:
                print(f"Error processing {model_path}: {str(e)}")

        # Print summary
        print("\nConversion Summary:")
        print(f"Processed {len(processed_models)} models:")
        for i, (src, dest) in enumerate(processed_models, 1):
            print(f"{i}. {os.path.basename(src)} -> {dest}")

    else:
        # Process a single model
        if not args.hf_dir or not args.lm_studio_dir:
            print("Error: --hf-dir and --lm-studio-dir are required unless using --all")
            return 1

        # Validate the Hugging Face directory
        hf_dir = os.path.expanduser(args.hf_dir)
        if not os.path.isdir(hf_dir):
            print(f"Error: Hugging Face directory '{hf_dir}' does not exist.")
            return 1

        # Check if the directory is likely a Hugging Face model directory
        if not (
            os.path.isdir(os.path.join(hf_dir, "blobs"))
            or os.path.isdir(os.path.join(hf_dir, "snapshots"))
            or os.path.exists(os.path.join(hf_dir, "config.json"))
        ):
            print(
                f"Warning: '{hf_dir}' does not look like a typical Hugging Face model directory"
            )

        lm_studio_dir = os.path.expanduser(args.lm_studio_dir)
        print(f"Converting model from {hf_dir} to {lm_studio_dir}")
        print(f"Using {'file copying' if args.copy else 'symbolic links'}")

        create_lmstudio_structure(hf_dir, lm_studio_dir, use_symlinks=not args.copy)

        print(f"Conversion complete! LM Studio model is ready at: {lm_studio_dir}")

    return 0


if __name__ == "__main__":
    exit(main())
