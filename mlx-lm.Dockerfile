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

# Copy the mlx-lm source code
COPY . /app/mlx-lm/

# Install MLX-LM from source and required packages
RUN cd /app/mlx-lm && \
    pip3 install -e . && \
    pip3 install fastapi uvicorn httpx litellm

# Copy entrypoint script
COPY ./docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]