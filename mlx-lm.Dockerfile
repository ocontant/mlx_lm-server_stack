FROM ubuntu:22.04

# Install system dependencies and troubleshooting tools
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    git \
    wget \
    curl \
    netcat-openbsd \
    iputils-ping \
    net-tools \
    tcpdump \
    nmap \
    lsof \
    htop \
    procps \
    vim \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel

# Set working directory
WORKDIR /app

# Fetch MLX-LM source from GitHub repository (optional: specify branch/tag with --branch)
ARG MLX_LM_REPO=https://github.com/ml-explore/mlx-lm.git
ARG MLX_LM_BRANCH=main
RUN git clone --depth 1 --branch ${MLX_LM_BRANCH} ${MLX_LM_REPO} /app/mlx-lm

# Install MLX-LM from source and required packages
RUN cd /app/mlx-lm && \
    pip3 install -e . && \
    pip3 install fastapi uvicorn httpx litellm

# Fetch additional repositories as needed
ARG EXTRA_REPO_URL=""
ARG EXTRA_REPO_BRANCH="main"
ARG EXTRA_REPO_DIR="/app/extra-repo"
RUN if [ ! -z "${EXTRA_REPO_URL}" ]; then \
        git clone --depth 1 --branch ${EXTRA_REPO_BRANCH} ${EXTRA_REPO_URL} ${EXTRA_REPO_DIR}; \
    fi

# Copy entrypoint script
COPY ./docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]