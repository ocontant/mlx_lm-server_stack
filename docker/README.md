# MLX-LM Docker Deployment

This directory contains Docker configuration for deploying MLX-LM with Traefik as a reverse proxy and LiteLLM for API compatibility.

## Overview

The setup includes:

1. **Traefik**: Reverse proxy for TLS termination and routing
2. **MLX-LM**: LLM service built from source code
3. **LiteLLM**: API compatibility layer to convert between different LLM API formats

## Prerequisites

- Docker and Docker Compose installed
- Hugging Face models accessible (default: mlx-community/Qwen2.5-Coder-32B-Instruct-8bit)
- SSL certificates for production use

## Configuration

### Environment Variables

Edit the `.env` file to configure:

```
# Traefik configuration
TRAEFIK_HOSTNAME=traefik.localhost.loc
TRAEFIK_DASHBOARD_PORT=8080

# MLX-LM configuration
MLX_HOSTNAME=mlx.localhost.loc
MLX_PORT=11432
MLX_MODEL=mlx-community/Qwen2.5-Coder-32B-Instruct-8bit

# LiteLLM configuration
LITELLM_HTTP_HOSTNAME=litellm.localhost.loc
LITELLM_PORT=11400

# Shared configuration
HF_CACHE_DIR=/root/.cache/huggingface/hub
```

### SSL Certificates

For production, place your SSL certificates in `traefik/certificates/`:

- `cert.pem`: SSL certificate
- `key.pem`: SSL private key

For development, generate self-signed certificates:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ./traefik/certificates/key.pem \
  -out ./traefik/certificates/cert.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
```

## Deployment

### Build and Start Services

```bash
# Build the MLX-LM image
docker-compose build

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f
```

### Accessing Services

- **Traefik Dashboard**: http://traefik.localhost.loc:8080
- **MLX-LM API**: http://mlx.localhost.loc
- **LiteLLM API**: http://litellm.localhost.loc (HTTP) or https://litellm.localhost.loc (HTTPS)
- **Traefik Metrics**: http://traefik.localhost.loc/metrics
- **Traefik Health**: http://traefik.localhost.loc/health

### Stopping Services

```bash
docker-compose down
```

## API Usage

### Direct MLX-LM API (OpenAI compatible)

```bash
curl -X POST http://mlx.localhost.loc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen2.5-Coder-32B-Instruct-8bit",
    "messages": [{"role": "user", "content": "Hello, how are you?"}]
  }'
```

### LiteLLM API (Multiple Provider Compatible)

```bash
# Using OpenAI format
curl -X POST http://litellm.localhost.loc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello, how are you?"}]
  }'

# Using Azure OpenAI format
curl -X POST http://litellm.localhost.loc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4-turbo",
    "messages": [{"role": "user", "content": "Hello, how are you?"}]
  }'

# Using Claude format
curl -X POST http://litellm.localhost.loc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-opus",
    "messages": [{"role": "user", "content": "Hello, how are you?"}]
  }'
```

## Customization

### Adding More Models

Edit the `litellm/config.yaml` file to add more models or model mappings.

### Scaling for Production

For production use:
1. Configure proper SSL certificates
2. Adjust rate limiting in Traefik configuration
3. Mount external volumes for persistent storage
4. Consider adding monitoring and alerting