# MLX LM Server

A Docker-based deployment solution for MLX LM models with Traefik reverse proxy and LiteLLM integration.

## Overview

This setup provides:

- MLX LM server running on Apple Silicon (macOS)
- Traefik reverse proxy with automatic HTTPS support
- LiteLLM for OpenAI-compatible API
- Docker-based setup for easy deployment

## Quick Start

1. Copy example config and customize:
   ```bash
   cp .env.example .env
   ```

2. Generate SSL certificates (choose one method):

   **Option 1: Self-signed certificates for local development**
   ```bash
   cd traefik/certificates
   ./generate-local-certs.sh --domain localhost.loc
   
   # Add to /etc/hosts
   echo "127.0.0.1 localhost.loc mlx.localhost.loc litellm.localhost.loc traefik.localhost.loc" | sudo tee -a /etc/hosts
   ```

   **Option 2: Let's Encrypt automatic SSL (for production)**
   
   Edit `.env` and set:
   ```
   AUTO_SSL=true
   CERT_RESOLVER=letsencrypt
   ```
   Update the email address in `traefik/config/letsencrypt.yaml`

3. Start the services:
   ```bash
   docker-compose up -d
   ```

4. Access services:
   - MLX LM server: https://mlx.localhost.loc (or your domain)
   - LiteLLM API: https://litellm.localhost.loc (or your domain)
   - Traefik dashboard: http://traefik.localhost.loc:8080 (customize port in .env)

## Configuration

### Environment Variables

See `.env.example` for available options:

- `MLX_MODEL`: HuggingFace model ID
- `AUTO_SSL`: Enable/disable automatic SSL with Let's Encrypt
- `CERT_RESOLVER`: Certificate resolver to use (letsencrypt, letsencrypt-dns)
- And more...

### Traefik Configuration

Traefik configuration files are located in:

- `traefik/config/traefik.yaml`: Main configuration
- `traefik/config/dynamic.yaml`: Dynamic configuration for services
- `traefik/config/letsencrypt.yaml`: Let's Encrypt configuration (when using automatic SSL)

## SSL Certificates

### Option 1: Self-signed certificates (Development)

Use the provided script to generate self-signed certificates:

```bash
cd traefik/certificates
./generate-local-certs.sh --domain localhost.loc
```

For custom domain names:
```bash
cd traefik/certificates
./generate-local-certs.sh --domain yourdomain.com --days 365
```

### Option 2: Automatic SSL with Let's Encrypt (Production)

1. Enable automatic SSL in `.env`:
   ```
   AUTO_SSL=true
   CERT_RESOLVER=letsencrypt
   ```

2. Configure your email in `traefik/config/letsencrypt.yaml`

3. Ensure your domain points to the server where you're running this setup

4. For wildcard certificates, configure DNS challenge provider

## LiteLLM Configuration

Edit `litellm/config.yaml` to configure model routing, caching, and other options.