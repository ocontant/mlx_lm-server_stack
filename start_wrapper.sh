#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
MLX Explore Comprehensive Wrapper

This script provides a complete solution for MLX Explore setup and runtime management:
1. Dependency management - installs pyenv, creates virtualenv, clones repositories
2. Service management - starts and monitors mlx_lm server and LiteLLM (via docker-compose)

Key Features:
- Dependency setup: pyenv, virtualenv, ml-explore/mlx-lm
- Process management with graceful shutdown
- Configurable service parameters via command line or .env file
- Signal handling for clean termination
- Smart dependency detection to avoid reinstalling existing components
"""

import os
import subprocess
import sys
import logging
import shutil
import signal
import argparse
import time
import json
from pathlib import Path
from typing import Dict, Any, Optional


def setup_logging(log_level: str = "INFO") -> logging.Logger:
    """
    Configure logging to output to both file and console.

    Args:
        log_level (str): Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)

    Returns:
        logging.Logger: Configured logger instance
    """
    level = getattr(logging, log_level.upper(), logging.INFO)

    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[
            logging.FileHandler("mlx_wrapper.log", encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )
    return logging.getLogger(__name__)


def load_env_file(env_path: str = ".env") -> Dict[str, str]:
    """
    Load environment variables from .env file.

    Args:
        env_path (str): Path to the .env file

    Returns:
        Dict[str, str]: Dictionary of environment variables
    """
    env_vars = {}

    try:
        if os.path.exists(env_path):
            with open(env_path, "r", encoding="utf-8") as file:
                for line in file:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue

                    key, value = line.split("=", 1)
                    # Remove quotes if present
                    value = value.strip("'\"")
                    env_vars[key.strip()] = value

            return env_vars
        else:
            return {}
    except Exception as e:
        print(f"Warning: Error loading .env file: {e}")
        return {}


class DependencyManager:
    """
    Manages dependency installation and setup for MLX Explore project.
    """

    def __init__(self, logger: logging.Logger, args: argparse.Namespace):
        """
        Initialize the DependencyManager with project-specific configurations.

        Args:
            logger (logging.Logger): Logger instance for tracking setup process
            args (argparse.Namespace): Command line arguments
        """
        self.logger = logger
        self.args = args
        self.dependency_config: Dict[str, Any] = {
            "REPO_URL": "https://github.com/ml-explore/mlx-explore",
            "REPO_DIR": Path(".repos/ml-explore"),
            "VENV_NAME": args.venv_name,
            "PYTHON_VERSION": args.python_version,
        }
        self.state: Dict[str, bool] = {
            "pyenv_installed": False,
            "pyenv_virtualenv_installed": False,
            "virtualenv_created": False,
            "ml_explore_cloned": False,
            "ml_explore_built": False,
            "mlx_lm_installed": False,
        }

    def command_exists(self, command: str) -> bool:
        """
        Check if a given command exists in the system path.

        Args:
            command (str): Command to check

        Returns:
            bool: True if command exists, False otherwise
        """
        return shutil.which(command) is not None

    def run_command(
        self, command: str, capture_output: bool = False
    ) -> subprocess.CompletedProcess:
        """
        Run a shell command with optional output capture.

        Args:
            command (str): Command to run
            capture_output (bool, optional): Whether to capture command output. Defaults to False.

        Returns:
            subprocess.CompletedProcess: Result of the command execution
        """
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=capture_output,
                text=True,
                check=True,
            )
            return result
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Command failed: {command}")
            self.logger.error(f"Error: {e}")
            raise

    def check_pyenv_installed(self) -> bool:
        """
        Check if pyenv is already installed and working.

        Returns:
            bool: True if pyenv is installed, False otherwise
        """
        if not self.command_exists("pyenv"):
            return False

        try:
            # Check if pyenv is properly set up and working
            result = self.run_command("pyenv --version", capture_output=True)
            if result.returncode == 0:
                self.logger.info(f"Pyenv is already installed: {result.stdout.strip()}")
                return True
            return False
        except Exception:
            return False

    def check_pyenv_virtualenv_installed(self) -> bool:
        """
        Check if pyenv-virtualenv plugin is installed.

        Returns:
            bool: True if pyenv-virtualenv is installed, False otherwise
        """
        try:
            # Check if pyenv-virtualenv commands are available
            result = self.run_command("pyenv virtualenv --help", capture_output=True)
            if result.returncode == 0:
                self.logger.info("Pyenv-virtualenv is already installed")
                return True
            return False
        except Exception:
            return False

    def install_pyenv(self) -> None:
        """
        Install pyenv and pyenv-virtualenv using Homebrew or universal installer.
        Skips installation if already installed.
        """
        try:
            # Check if pyenv is already installed
            if self.check_pyenv_installed():
                self.state["pyenv_installed"] = True
                self.logger.info("Using existing pyenv installation")
            else:
                if self.command_exists("brew"):
                    self.logger.info("Installing pyenv via Homebrew")
                    self.run_command("brew install pyenv pyenv-virtualenv")
                else:
                    self.logger.info("Installing pyenv using universal script")
                    install_script = "curl https://pyenv.run | bash"
                    self.run_command(install_script)

            # Verify pyenv installation
            if not self.command_exists("pyenv"):
                raise RuntimeError("Pyenv installation failed")

            self.state["pyenv_installed"] = True
            self.logger.info("Pyenv installed successfully")

            # Check if pyenv-virtualenv is already installed
            if self.check_pyenv_virtualenv_installed():
                self.state["pyenv_virtualenv_installed"] = True
                self.logger.info("Using existing pyenv-virtualenv installation")
            else:
                if self.command_exists("brew"):
                    self.logger.info("Installing pyenv-virtualenv via Homebrew")
                    self.run_command("brew install pyenv-virtualenv")
                else:
                    self.logger.info("Pyenv-virtualenv should be included in pyenv.run")

                self.state["pyenv_virtualenv_installed"] = True
                self.logger.info("Pyenv-virtualenv installed successfully")

        except Exception as e:
            self.logger.error(f"Pyenv/pyenv-virtualenv installation failed: {e}")
            sys.exit(1)

    def check_virtualenv_exists(self, venv_name: str) -> bool:
        """
        Check if a virtualenv with the given name already exists.

        Args:
            venv_name (str): Name of the virtualenv to check

        Returns:
            bool: True if virtualenv exists, False otherwise
        """
        try:
            result = self.run_command("pyenv virtualenvs", capture_output=True)
            return venv_name in result.stdout
        except Exception:
            return False

    def create_virtualenv(self, python_version: Optional[str] = None) -> None:
        """
        Create a virtual environment using pyenv.
        Skip creation if virtualenv already exists.

        Args:
            python_version (str, optional): Python version to use. Defaults to config version.
        """
        python_version = python_version or self.dependency_config["PYTHON_VERSION"]
        venv_name = self.dependency_config["VENV_NAME"]

        try:
            # Check if virtualenv already exists
            if self.check_virtualenv_exists(venv_name):
                self.logger.info(f"Virtualenv '{venv_name}' already exists, using it")
                self.run_command(f"pyenv activate {venv_name}")
                self.state["virtualenv_created"] = True
                return

            # Install Python version if not available
            self.logger.info(
                f"Installing Python {python_version} if not already available"
            )
            self.run_command(f"pyenv install -s {python_version}")

            # Create virtualenv
            self.logger.info(
                f"Creating virtualenv '{venv_name}' with Python {python_version}"
            )
            self.run_command(f"pyenv virtualenv {python_version} {venv_name}")
            self.run_command(f"pyenv activate {venv_name}")

            self.state["virtualenv_created"] = True
            self.logger.info(f"Virtualenv {venv_name} created and activated")
        except Exception as e:
            self.logger.error(f"Virtualenv creation failed: {e}")
            sys.exit(1)

    def check_repository_exists(self) -> bool:
        """
        Check if MLX Explore repository is already cloned.

        Returns:
            bool: True if repository exists, False otherwise
        """
        repo_dir = self.dependency_config["REPO_DIR"]
        git_dir = repo_dir / ".git"
        return repo_dir.exists() and git_dir.exists()

    def clone_repository(self) -> None:
        """
        Clone the MLX Explore repository if not already present.
        """
        repo_dir = self.dependency_config["REPO_DIR"]
        repo_url = self.dependency_config["REPO_URL"]

        try:
            if self.check_repository_exists():
                self.logger.info(f"MLX Explore repository already exists at {repo_dir}")
                self.state["ml_explore_cloned"] = True
                return

            if not repo_dir.exists():
                repo_dir.parent.mkdir(parents=True, exist_ok=True)
                self.logger.info(f"Cloning repository from {repo_url} to {repo_dir}")
                self.run_command(f"git clone {repo_url} {repo_dir.resolve()}")
                self.state["ml_explore_cloned"] = True
            else:
                self.logger.info("MLX Explore repository already exists")
                self.state["ml_explore_cloned"] = True
        except Exception as e:
            self.logger.error(f"Repository cloning failed: {e}")
            sys.exit(1)

    def check_mlx_lm_installed(self) -> bool:
        """
        Check if mlx-lm is already installed.

        Returns:
            bool: True if mlx-lm is installed, False otherwise
        """
        try:
            # Try to import the module to check if it's installed
            result = self.run_command(
                "python -c \"import importlib.util; print(importlib.util.find_spec('mlx_lm') is not None)\"",
                capture_output=True,
            )
            return "True" in result.stdout
        except Exception:
            return False

    def build_and_install_dependencies(self) -> None:
        """
        Attempt to build and install ml-explore from source.
        Fallback to installing mlx-lm from pip if source build fails.
        Skips installation if already installed.
        """
        # First check if mlx-lm is already installed
        if self.check_mlx_lm_installed():
            self.logger.info("mlx-lm is already installed in the current environment")
            self.state["mlx_lm_installed"] = True
            return

        try:
            # Try to install from source
            repo_dir = self.dependency_config["REPO_DIR"]
            self.logger.info(f"Installing ml-explore from source at {repo_dir}")
            self.run_command(f"pip install -e {repo_dir.resolve()}")
            self.state["ml_explore_built"] = True
            self.logger.info("Successfully installed ml-explore from source")
        except Exception as e:
            self.logger.warning(f"ml-explore source installation failed: {e}")
            self.logger.info("Falling back to pip installation of mlx-lm")
            try:
                self.run_command("pip install --upgrade mlx-lm")
                self.state["mlx_lm_installed"] = True
                self.logger.info("Successfully installed mlx-lm from pip")
            except Exception as install_err:
                self.logger.error(f"Dependency installation failed: {install_err}")
                sys.exit(1)

    def setup_dependencies(self) -> None:
        """
        Orchestrate the entire dependency setup process.
        """
        self.logger.info("Starting MLX Explore dependency setup")

        # Install pyenv and create virtualenv
        if not self.state["pyenv_installed"]:
            self.install_pyenv()

        if not self.state["virtualenv_created"]:
            self.create_virtualenv()

        # Clone repository and install dependencies
        if not self.state["ml_explore_cloned"]:
            self.clone_repository()

        if not (self.state["ml_explore_built"] or self.state["mlx_lm_installed"]):
            self.build_and_install_dependencies()

        self.logger.info("MLX Explore dependency setup completed successfully")


class ServiceManager:
    """
    Manages the MLX service and Docker Compose processes.
    """

    def __init__(self, logger: logging.Logger, args: argparse.Namespace):
        """
        Initialize service manager.

        Args:
            logger (logging.Logger): Logger instance
            args (argparse.Namespace): Command line arguments
        """
        self.logger = logger
        self.args = args
        self.mlx_process = None
        self.docker_process = None

        # Set up signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def start_mlx_service(self) -> subprocess.Popen:
        """
        Start the MLX service with the specified parameters.

        Returns:
            subprocess.Popen: Process handle for the MLX service
        """
        env = os.environ.copy()
        env["MLX_MODEL"] = self.args.model
        env["MLX_PORT"] = str(self.args.port)
        env["MLX_HOST"] = self.args.host
        env["LOG_LEVEL"] = self.args.log_level
        env["TRUST_REMOTE_CODE"] = "true" if self.args.trust_remote_code else "false"
        env["EOS_TOKEN"] = self.args.eos_token or ""
        env["EXTRA_ARGS"] = self.args.extra_args or ""

        self.logger.info(
            f"Starting MLX service on {self.args.host}:{self.args.port} with model {self.args.model}"
        )

        try:
            process = subprocess.Popen(
                ["bash", "entrypoint.sh"],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,  # Line buffered
            )
            self.mlx_process = process

            # Start a thread to continuously process output
            import threading

            def log_output(process):
                for line in process.stdout:
                    self.logger.info(f"[MLX] {line.strip()}")

            threading.Thread(target=log_output, args=(process,), daemon=True).start()

            return process
        except Exception as e:
            self.logger.error(f"Failed to start MLX service: {e}")
            raise

    def start_docker_compose(self) -> subprocess.Popen:
        """
        Start the Docker Compose services.

        Returns:
            subprocess.Popen: Process handle for Docker Compose
        """
        self.logger.info("Starting LiteLLM via Docker Compose...")

        try:
            # Check if docker-compose is installed
            if not shutil.which("docker-compose") and not shutil.which("docker"):
                self.logger.error(
                    "Docker Compose not found. Please install Docker Desktop or Docker Compose."
                )
                sys.exit(1)

            # Use docker compose command if available (newer Docker versions)
            docker_compose_cmd = "docker-compose"
            if shutil.which("docker") and not shutil.which("docker-compose"):
                docker_compose_cmd = "docker compose"

            process = subprocess.Popen(
                f"{docker_compose_cmd} up -d",
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,  # Line buffered
            )
            self.docker_process = process

            # Start a thread to continuously process output
            import threading

            def log_output(process):
                for line in process.stdout:
                    self.logger.info(f"[Docker] {line.strip()}")

            threading.Thread(target=log_output, args=(process,), daemon=True).start()

            return process
        except Exception as e:
            self.logger.error(f"Failed to start Docker Compose: {e}")
            raise

    def _signal_handler(self, sig: int, frame: Any) -> None:
        """
        Handle signals like SIGINT and SIGTERM.

        Args:
            sig (int): Signal number
            frame (Any): Current stack frame
        """
        self.logger.info(f"Caught signal: {sig}")
        self.cleanup()
        sys.exit(0)

    def cleanup(self) -> None:
        """
        Clean up resources and stop services.
        """
        self.logger.info("Cleaning up services...")

        # Stop Docker Compose
        if self.docker_process and self.docker_process.poll() is None:
            self.logger.info("Stopping Docker Compose...")
            try:
                # Use docker compose command if available (newer Docker versions)
                docker_compose_cmd = "docker-compose"
                if shutil.which("docker") and not shutil.which("docker-compose"):
                    docker_compose_cmd = "docker compose"

                subprocess.run(f"{docker_compose_cmd} down", shell=True, check=True)
                self.logger.info("Docker Compose services stopped")
            except Exception as e:
                self.logger.error(f"Error stopping Docker Compose: {e}")

        # Stop MLX service
        if self.mlx_process and self.mlx_process.poll() is None:
            self.logger.info("Terminating MLX service...")
            self.mlx_process.terminate()
            try:
                self.mlx_process.wait(timeout=5)
                self.logger.info("MLX service terminated")
            except subprocess.TimeoutExpired:
                self.logger.warning("MLX service didn't terminate in time, forcing...")
                self.mlx_process.kill()
                self.logger.info("MLX service killed")

        self.logger.info("Cleanup completed. Exiting.")

    def run_services(self) -> None:
        """
        Start and manage all services.
        """
        try:
            # Start MLX service
            self.mlx_process = self.start_mlx_service()

            # Wait a bit for MLX to start before launching Docker services
            time.sleep(3)

            # Start Docker Compose services if not skipped
            if not self.args.skip_docker:
                self.docker_process = self.start_docker_compose()
            else:
                self.logger.info("Docker Compose services skipped")

            # Wait for MLX process to complete (will generally run until terminated)
            self.logger.info("Services started successfully. Press Ctrl+C to stop.")
            self.mlx_process.wait()

        except KeyboardInterrupt:
            self.logger.info("Interrupted by user")
        except Exception as e:
            self.logger.error(f"Error running services: {e}")
        finally:
            self.cleanup()


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="MLX Explore Wrapper: Setup dependencies and run services",
        epilog="Additional commands:\n  --generate-env-template    Generate a template .env file with default values.",
    )

    # Environment file option
    parser.add_argument(
        "--env-file",
        default=".env",
        help="Path to environment file (.env)",
    )

    # Dependency setup options
    dep_group = parser.add_argument_group("Dependency Setup Options")
    dep_group.add_argument(
        "--skip-deps",
        action="store_true",
        help="Skip dependency setup step",
    )
    dep_group.add_argument(
        "--python-version",
        default="3.12.9",
        help="Python version to use for virtualenv",
    )
    dep_group.add_argument(
        "--venv-name",
        default="mlx",
        help="Name for the virtual environment",
    )

    # Service options
    service_group = parser.add_argument_group("Service Options")
    service_group.add_argument(
        "--model",
        default="",
        help="MLX model name. E.g. 'mlx-community/Qwen2.5-Coder-32B-Instruct-8bit'",
    )
    service_group.add_argument(
        "--host",
        default="127.0.0.1",
        help="MLX service host",
    )
    service_group.add_argument(
        "--port",
        type=int,
        default=11432,
        help="MLX service port",
    )
    service_group.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Log level",
    )
    service_group.add_argument(
        "--trust-remote-code",
        action="store_true",
        help="Enable trust_remote_code",
    )
    service_group.add_argument(
        "--eos-token",
        default="",
        help='Custom EOS token. E.g. "<|endoftext|>"',
    )
    service_group.add_argument(
        "--extra-args",
        default="",
        help="Additional args to pass to entrypoint.sh",
    )
    service_group.add_argument(
        "--skip-docker",
        action="store_true",
        help="Skip starting Docker Compose services",
    )

    # Parse arguments
    args = parser.parse_args()

    # Load environment variables from .env file
    env_vars = load_env_file(args.env_file)

    # Update arguments with environment variables (if not already set via command line)
    # First, get the defaults
    defaults = {
        action.dest: action.default
        for action in parser._actions
        if action.dest != "help"
    }

    # For each argument that matches its default (i.e., wasn't set on command line),
    # check if there's an environment variable to use instead
    for arg_name, default_value in defaults.items():
        # Convert arg_name (e.g., log_level) to env var format (e.g., LOG_LEVEL)
        env_name = arg_name.upper().replace("-", "_")

        # For boolean flags, check if they're at default value
        if isinstance(default_value, bool):
            if getattr(args, arg_name) == default_value and env_name in env_vars:
                # Convert string to boolean
                env_value = env_vars[env_name].lower() in ("true", "yes", "1", "y")
                setattr(args, arg_name, env_value)
        # For regular arguments, check if they're at default value
        elif getattr(args, arg_name) == default_value and env_name in env_vars:
            # Convert to appropriate type based on default value
            if isinstance(default_value, int):
                setattr(args, arg_name, int(env_vars[env_name]))
            else:
                setattr(args, arg_name, env_vars[env_name])

    return args


def generate_env_template() -> None:
    """
    Generate a template .env file with default values.
    """
    env_content = """# MLX Explore Wrapper Configuration
# This file contains environment variables for the MLX Explore wrapper
# Uncomment and modify values as needed

# Dependency Setup Options
SKIP_DEPS=false
PYTHON_VERSION=3.12.9
VENV_NAME=mlx-test

# Service Options
MODEL=mlx-community/Qwen2.5-Coder-32B-Instruct-8bit
HOST=127.0.0.1
PORT=11432
LOG_LEVEL=INFO
TRUST_REMOTE_CODE=false
EOS_TOKEN="<|endoftext|>"
EXTRA_ARGS=
SKIP_DOCKER=false
"""

    # Check if .env file already exists
    if os.path.exists(".env"):
        print(".env file already exists. Not overwriting.")
        return

    # Write the template
    with open(".env", "w", encoding="utf-8") as f:
        f.write(env_content)

    print(".env template file generated successfully.")


def main():
    """
    Main entry point for the MLX Explore wrapper.
    """
    # Check for --generate-env-template flag before regular parsing
    if len(sys.argv) > 1 and sys.argv[1] == "--generate-env-template":
        generate_env_template()
        sys.exit(0)

    args = parse_arguments()
    logger = setup_logging(args.log_level)

    logger.info("Starting MLX Explore wrapper")

    # Log configuration
    config_summary = {
        "Model": args.model,
        "Host:Port": f"{args.host}:{args.port}",
        "Trust Remote Code": args.trust_remote_code,
        "Skip Dependencies": args.skip_deps,
        "Skip Docker": args.skip_docker,
        "Log Level": args.log_level,
        "Virtual Environment": args.venv_name,
        "Python Version": args.python_version,
    }
    logger.info(f"Configuration: {json.dumps(config_summary, indent=2)}")

    try:
        # Step 1: Set up dependencies (unless skipped)
        if not args.skip_deps:
            logger.info("Setting up dependencies...")
            dependency_manager = DependencyManager(logger, args)
            dependency_manager.setup_dependencies()
        else:
            logger.info("Dependency setup skipped")

        # Step 2: Start services
        logger.info("Starting services...")
        service_manager = ServiceManager(logger, args)
        service_manager.run_services()

    except Exception as e:
        logger.error(f"Wrapper execution failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
