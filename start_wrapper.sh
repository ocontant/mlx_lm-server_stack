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
- Configurable service parameters
- Signal handling for clean termination
"""

import os
import subprocess
import sys
import logging
import shutil
import signal
import argparse
import time
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


class DependencyManager:
    """
    Manages dependency installation and setup for MLX Explore project.
    """

    def __init__(self, logger: logging.Logger):
        """
        Initialize the DependencyManager with project-specific configurations.

        Args:
            logger (logging.Logger): Logger instance for tracking setup process
        """
        self.logger = logger
        self.dependency_config: Dict[str, Any] = {
            "REPO_URL": "https://github.com/ml-explore/mlx-explore",
            "REPO_DIR": Path(".repos/ml-explore"),
            "VENV_NAME": "mlx-test",
            "PYTHON_VERSION": "3.12.9",
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

    def install_pyenv(self) -> None:
        """
        Install pyenv and pyenv-virtualenv using Homebrew or universal installer.
        """
        try:
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
        except Exception as e:
            self.logger.error(f"Pyenv installation failed: {e}")
            sys.exit(1)

    def create_virtualenv(self, python_version: Optional[str] = None) -> None:
        """
        Create a virtual environment using pyenv.

        Args:
            python_version (str, optional): Python version to use. Defaults to config version.
        """
        python_version = python_version or self.dependency_config["PYTHON_VERSION"]
        venv_name = self.dependency_config["VENV_NAME"]

        try:
            # Install Python version if not available
            self.run_command(f"pyenv install -s {python_version}")

            # Create virtualenv
            self.run_command(f"pyenv virtualenv {python_version} {venv_name}")
            self.run_command(f"pyenv activate {venv_name}")

            self.state["virtualenv_created"] = True
            self.logger.info(f"Virtualenv {venv_name} created and activated")
        except Exception as e:
            self.logger.error(f"Virtualenv creation failed: {e}")
            sys.exit(1)

    def clone_repository(self) -> None:
        """
        Clone the MLX Explore repository if not already present.
        """
        repo_dir = self.dependency_config["REPO_DIR"]
        repo_url = self.dependency_config["REPO_URL"]

        try:
            if not repo_dir.exists():
                repo_dir.parent.mkdir(parents=True, exist_ok=True)
                self.run_command(f"git clone {repo_url} {repo_dir.resolve()}")
                self.state["ml_explore_cloned"] = True
            else:
                self.logger.info("MLX Explore repository already exists")
        except Exception as e:
            self.logger.error(f"Repository cloning failed: {e}")
            sys.exit(1)

    def build_and_install_dependencies(self) -> None:
        """
        Attempt to build and install ml-explore from source.
        Fallback to installing mlx-lm from pip if source build fails.
        """
        try:
            # Try to install from source
            repo_dir = self.dependency_config["REPO_DIR"]
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
            mlx_process = self.start_mlx_service()

            # Wait a bit for MLX to start before launching Docker services
            time.sleep(3)

            # Start Docker Compose services
            docker_process = self.start_docker_compose()

            # Wait for MLX process to complete (will generally run until terminated)
            self.logger.info("Services started successfully. Press Ctrl+C to stop.")
            mlx_process.wait()

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
        description="MLX Explore Wrapper: Setup dependencies and run services"
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

    # Service options
    service_group = parser.add_argument_group("Service Options")
    service_group.add_argument(
        "--model",
        default="mlx-community/Qwen2.5-Coder-32B-Instruct-8bit",
        help="MLX model name",
    )
    service_group.add_argument(
        "--host",
        default="0.0.0.0",
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
        help="Custom EOS token",
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

    return parser.parse_args()


def main():
    """
    Main entry point for the MLX Explore wrapper.
    """
    args = parse_arguments()
    logger = setup_logging(args.log_level)

    logger.info("Starting MLX Explore wrapper")

    try:
        # Step 1: Set up dependencies (unless skipped)
        if not args.skip_deps:
            logger.info("Setting up dependencies...")
            dependency_manager = DependencyManager(logger)
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
