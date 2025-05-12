#!/usr/bin/env python3

import subprocess
import signal
import argparse
import os
import sys

# Keep global references to processes for cleanup
mlx_process = None
docker_process = None

def clean():
    print("\n[Wrapper] Cleaning up...")
    global mlx_process, docker_process

    if docker_process and docker_process.poll() is None:
        printf("-"*50)
        print("[Wrapper] Stopping Docker Compose...")
        subprocess.run(["docker-compose", "down"])
        

    if mlx_process and mlx_process.poll() is None:
        printf("-"*50)
        print("[Wrapper] Terminating MLX service...")
        mlx_process.terminate()
        try:
            mlx_process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            mlx_process.kill()
    
    printf("-"*50)
    print("[Wrapper] Clean exit.")

def signal_handler(sig, frame):
    printf("*"*10)
    print(f"\n[Wrapper] Caught signal: {sig}")
    printf("*"*10)
    clean()
    sys.exit(0)

def start_mlx_service(args):
    env = os.environ.copy()
    env["MLX_MODEL"] = args.model
    env["MLX_PORT"] = str(args.port)
    env["MLX_HOST"] = args.host
    env["LOG_LEVEL"] = args.log_level
    env["TRUST_REMOTE_CODE"] = "true" if args.trust_remote_code else "false"
    env["EOS_TOKEN"] = args.eos_token or ""
    env["EXTRA_ARGS"] = args.extra_args or ""

    print(f"[Wrapper] Starting MLX service on {args.host}:{args.port} with model {args.model}")
    return subprocess.Popen(
        ["bash", "entrypoint.sh"],
        env=env,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )

def start_docker_compose():
    print("[Wrapper] Starting LiteLLM via Docker Compose...")
    return subprocess.Popen(
        ["docker-compose", "up", "-d"],
        stdout=sys.stdout,
        stderr=sys.stderr,
    )

def parse_args():
    parser = argparse.ArgumentParser(description="Wrapper to start MLX and LiteLLM together.")
    parser.add_argument("--model", default="mlx-community/Qwen2.5-Coder-32B-Instruct-8bit", help="MLX model name")
    parser.add_argument("--host", default="0.0.0.0", help="MLX host")
    parser.add_argument("--port", type=int, default=11432, help="MLX port")
    parser.add_argument("--log-level", default="INFO", help="Log level")
    parser.add_argument("--trust-remote-code", action="store_true", help="Enable trust_remote_code")
    parser.add_argument("--eos-token", default="", help="Custom EOS token")
    parser.add_argument("--extra-args", default="", help="Additional args to pass to entrypoint.sh")

    return parser.parse_args()

def main():
    global mlx_process, docker_process

    # Trap SIGINT/SIGTERM
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    args = parse_args()

    mlx_process = start_mlx_service(args)
    docker_process = start_docker_compose()

    try:
        # Wait for the MLX service to finish (normally won't unless it crashes)
        mlx_process.wait()
    except KeyboardInterrupt:
        pass
    finally:
        clean()

if __name__ == "__main__":
    main()
