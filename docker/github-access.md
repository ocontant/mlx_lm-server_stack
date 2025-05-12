# Accessing Private GitHub Repositories in Docker

This guide explains how to securely access private GitHub repositories when building Docker images.

## Method 1: SSH Keys (Recommended for Development)

1. **Create a deploy key in your GitHub repository**:
   - Generate an SSH key pair: 
     ```bash
     ssh-keygen -t ed25519 -C "deploy-key" -f ./deploy_key
     ```
   - Add the public key (deploy_key.pub) as a deploy key in your GitHub repository settings
   - Make sure to enable "Allow write access" if needed

2. **Build with the SSH key**:
   ```bash
   docker build \
     --build-arg SSH_PRIVATE_KEY="$(cat ./deploy_key)" \
     --build-arg MLX_LM_REPO=git@github.com:username/private-repo.git \
     -f mlx-lm.Dockerfile .
   ```

## Method 2: Personal Access Tokens (Easier for CI/CD)

1. **Create a GitHub Personal Access Token**:
   - Go to GitHub Settings → Developer Settings → Personal Access Tokens
   - Create a token with `repo` scope (or appropriate permissions for your repo)

2. **Use the token in the repo URL**:
   ```bash
   docker build \
     --build-arg MLX_LM_REPO=https://username:token@github.com/username/private-repo.git \
     -f mlx-lm.Dockerfile .
   ```

3. **Or use Git credential helper in Dockerfile**:
   ```
   RUN git config --global credential.helper store && \
       echo "https://username:token@github.com" > ~/.git-credentials
   ```

## Method 3: GitHub Actions Secrets (For CI/CD)

If using GitHub Actions, use repository secrets:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Docker image
        env:
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
        run: |
          docker build \
            --build-arg MLX_LM_REPO=https://username:${GH_TOKEN}@github.com/username/private-repo.git \
            -f mlx-lm.Dockerfile .
```

## Security Considerations

1. **Avoid embedding credentials in images**:
   - Use multi-stage builds to prevent credentials from being in the final image
   - Never hardcode tokens in Dockerfiles

2. **For the Dockerfile in this project**:
   - Modify the Dockerfile to handle SSH authentication:

```dockerfile
# Add this before the git clone commands
ARG SSH_PRIVATE_KEY=""
RUN if [ ! -z "${SSH_PRIVATE_KEY}" ]; then \
      mkdir -p /root/.ssh && \
      echo "${SSH_PRIVATE_KEY}" > /root/.ssh/id_ed25519 && \
      chmod 600 /root/.ssh/id_ed25519 && \
      ssh-keyscan github.com >> /root/.ssh/known_hosts; \
    fi
```