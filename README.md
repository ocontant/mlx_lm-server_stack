# MLX LM Server

A Docker-based deployment solution for MLX LM models with Traefik reverse proxy and LiteLLM integration, designed for Apple Silicon.

## Overview

This project provides a complete server setup for running MLX LM models with:

- MLX LM server for efficient inference on Apple Silicon
- Traefik reverse proxy with automatic HTTPS support
- LiteLLM integration for OpenAI-compatible API endpoints
- Docker-based orchestration for all components
- Support for model aliasing (e.g., map "gpt-4" to your local models)
- Anthropic API emulation for compatibility with Claude clients

## The wrapper script provides:

- Automatic dependency installation (pyenv, Python, MLX LM)
- Environment file generation and management
- Docker service orchestration (start/stop)
- Graceful shutdown and cleanup on SIGINT/SIGTERM
- Consolidated logging from all component

## Quick Start

Usage
```bash
./start_wrapper.py -h
usage: start_wrapper.py [-h] [--env-file ENV_FILE] [--skip-deps]  [--skip-docker] 
[--python-version PYTHON_VERSION] [--venv-name VENV_NAME] [--model MODEL] [--host HOST] 
[--port PORT] [--log-level {DEBUG,INFO,WARNING,ERROR,CRITICAL}] [--trust-remote-code] 
[--extra-args EXTRA_ARGS]

--------------------------------------------------------------------------------------------------

MLX Explore Wrapper: Setup dependencies and run services

options:
  -h, --help                        show this help message and exit
  --env-file ENV_FILE               Path to environment file (.env)

Dependency Setup Options:
  --skip-deps                       Skip dependency setup step
  --python-version PYTHON_VERSION   Python version to use for virtualenv
  --venv-name VENV_NAME             Name for the virtual environment

Service Options:
  --model MODEL                     MLX model name. E.g. 'mlx-community/Qwen2.5-Coder-32B-Instruct-8bit'
  --host HOST                       MLX service host
  --port PORT                       MLX service port
  --log-level {DEBUG,INFO,WARNING,ERROR,CRITICAL} Log level
  --trust-remote-code               Enable trust_remote_code
  --extra-args EXTRA_ARGS           Additional args to pass to mlx_lm-server_start.sh
  --skip-docker                     Skip starting Docker Compose services

Additional commands: --generate-env-template Generate a template .env file with default values.

--------------------------------------------------------------------------------------------------
```

### Using the Wrapper Script (Recommended)

The wrapper script automates the entire setup process:

```bash
# Generate environment template
./start_wrapper.py --generate-env-template
cp .env.example .env # Edit default values + argparse override .env value

# Start with basic configuration (handles everything)
./start_wrapper.py --model mlx-community/Mistral-7B-Instruct-v0.3-8bit

# Start with advanced options
./start_wrapper.py \
  --model mlx-community/Qwen2.5-Coder-32B-Instruct-8bit \
  --host 127.0.0.1 \
  --port 11432 \
  --log-level DEBUG \
  --trust-remote-code
```



### Manual Setup

If you prefer manual setup:

1. Copy example config and customize:

   ```bash
   cp .env.example .env
   ```

2. Generate SSL certificates (choose one method):

   **Option 1: Self-signed certificates for local development**

   ```bash
   cd tools
   ./generate_tlscerts.sh -g localhost.loc -a
   
   # Add to /etc/hosts
   echo "127.0.0.1 localhost.loc mlx.localhost.loc litellm.localhost.loc traefik.localhost.loc" | sudo tee -a /etc/hosts
   ```

   **Option 2: Let's Encrypt automatic SSL (for production)**

   Edit `.env` and set:

   ```bash
   AUTO_SSL=true
   CERT_RESOLVER=letsencrypt
   ```

   Update the email address in `traefik/config/letsencrypt.yaml`

   Update traefik route in `docker-compose.yml`

   ```yaml
   services:
      traefik:
         # ... other configurations ...
         command:
            # ... other commands ...
            - "--certificatesresolvers.letsencrypt.acme.email=your-email@example.com"
            - "--certificatesresolvers.letsencrypt.acme.storage=/etc/traefik/acme/acme.json"
            - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
            - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
   ```

   ```yaml
   litellm:
    labels:
      # To redirect Anthropic HTTPS endpoint to local API mlx-server
      - "traefik.http.routers.anthropic-https.rule=Host(`api.anthropic.com`)"
      - "traefik.http.routers.anthropic-https.entrypoints=websecure"
      - "traefik.http.routers.anthropic-https.service=litellm"
      - "traefik.http.routers.anthropic-https.tls=true"
      - "traefik.http.routers.anthropic-https.tls.certresolver=letsencrypt"
   ```

3. Start the services:

   #### Example starting using argparser to start the wrapper with the following options:

   ```bash
      ./start_wrapper.py --venv-name mlx-test --model mlx-community/Llama-4-Scout-17B-16E-Instruct-8bit --host 127.0.0.1 --port 11432 --log-level DEBUG
   ```
   
   #### You can also rely on .env to define parameters

   ```bash
      ./start_wrapper.py
   ```
   
   #### For special model families that need additional params

   ```bash
      ./start_wrapper.py --venv-name mlx-test --model mlx-community/Qwen2.5-Coder-32B-Instruct-8bit --host 127.0.0.1 --port 11432 --trust-remote-code --log-level DEBUG
   ```

4. Access services:

   - MLX LM API: <https://mlx.localhost.loc> (or your domain)
   - LiteLLM API: <https://litellm.localhost.loc> (or your domain)
   - Traefik dashboard: <http://traefik.localhost.loc:8080>

## Configuration

### Environment Variables

Key environment variables in `.env`:

- `MLX_MODEL`: HuggingFace model ID
- `TRUST_REMOTE_CODE`: Set to "true" for models requiring remote code execution
- `AUTO_SSL`: Enable/disable automatic SSL with Let's Encrypt
- `CERT_RESOLVER`: Certificate resolver to use (selfsigned, letsencrypt)

### LiteLLM Configuration

Edit `litellm/config.yaml` to customize:

- Model routing and aliases
- API endpoint mapping
- Default models for each API type
- Custom fallback behaviors

### Special Model Requirements

Some model families require special configuration:

1. **Qwen models**:
   - Require `trust_remote_code=True` and `eos_token="<|endoftext|>"`
   {@note: eos_token cannot be passed as parameter to mlx_lm.server at the moment. Client must implement stop token itself for now, or mlx_lm.server return crash error (trap and recover with wrapper.)}
   - Use with: `MLX_MODEL=mlx-community/Qwen2.5-Coder-14B-Instruct-8bit TRUST_REMOTE_CODE=true`

2. **Other special models**:
   - See `docs/MODEL_CONFIGS.md` for specific requirements

## Architecture

1. **MLX LM Server** - Core inference engine for Apple Silicon
2. **Traefik Proxy** - Handles routing, SSL termination, and load balancing
3. **LiteLLM Service** - Provides OpenAI-compatible API and model routing
4. **Wrapper Script** - Manages dependencies and process lifecycle

## API Compatibility

The server supports the following API formats:

- **OpenAI-compatible endpoints**: `/v1/chat/completions`, `/v1/completions`, etc.
- **Anthropic-compatible**: Via API emulation at the same endpoint as Claude
- **LiteLLM unified API**: For consistent access to multiple model providers

## Certificate Management

```bash
# Generate self-signed certificates for development
cd tools
./generate_tlscerts.sh -g localhost.loc -a

# Generate self-signed certificates for a specific domain
./generate_tlscerts.sh -g api.example.com -a

# Compare certificates for debugging
## Configure the cert_config.txt file with the appropriate domain and path to the certificate to compare with
./compare_certs.sh
```

## Current Issues

- **Self-signed SSL for External API Endpoints**: There are challenges with deploying custom self-signed SSL certificates for host-based endpoints like `api.anthropic.com`. This is needed to support agentic tools with hardcoded external API calls by redirecting them to local API and LLM models.

## Roadmap / TODO

- Docker compose down doesn't work during clean() process. Consider to use Docker SDK to have more control, instead of depending on external shell command.
- Automate registering environment variables to force Node.js to accept self-signed certificates.
- Integrate SSL self-signed certificate generation via argparse function in the wrapper script.
- Create a wizard in the wrapper script for Let's Encrypt configuration through argparse.
- Optional: Integrate observability and instrumentation in the stack.
- Add support for running a small autocomplete model concurrently (for powerful workstations).
- In dependencies, generate configuration for Aider, Continue, and other AI coding tools.
- Add support to download models from within wrapper using huggingface-cli tool.
- Other interesting logic would be to serve a default model, while a new model is being downloaded.

## About MLX

MLX LM is built on [MLX](https://github.com/ml-explore/mlx), a high-performance framework for machine learning on Apple Silicon. For more information about the base MLX LM package, see the [MLX LM GitHub repository](https://github.com/ml-explore/mlx-lm).

## About Litellm

Litellm is a lightweight Python library for interacting with large language models (LLMs) and generative AI models. It provides a simple and intuitive interface for calling LLMs and generative AI models, and supports a variety of popular LLMs and generative AI models, including OpenAI, Anthropic,). [litellm GitHub repository](https://github.com/BerriAI/litellm).

## About Traefik

Traefik is a modern HTTP reverse proxy and load balancer designed for containerized and cloud-native environments. Its dynamic configuration abilities and strong integration with major infrastructure platforms make it a popular choice for microservices architectures. [Traefik](https://github.com/traefik/traefik)
