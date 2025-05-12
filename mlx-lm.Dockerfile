FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYENV_ROOT="/root/.pyenv"
ENV PATH="${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:$PATH"

# Install system dependencies and troubleshooting tools
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    wget \
    llvm \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    ca-certificates \
    make \
    netcat-openbsd \
    iputils-ping \
    net-tools \
    tcpdump \
    nmap \
    lsof \
    htop \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install pyenv and pyenv-virtualenv
RUN curl https://pyenv.run | bash

# Ensure pyenv and pyenv-virtualenv are available in the shell
RUN echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc && \
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc && \
    echo 'eval "$(pyenv init --path)"' >> ~/.bashrc && \
    echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc

# Install Python 3.12.9 and create a virtualenv
RUN bash -c 'pyenv install 3.12.9 && eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init -)" && \
    pyenv virtualenv 3.12.9 mlx-venv && \
    pyenv global mlx-venv && \
    pyenv rehash'
RUN python -m pip install --upgrade pip
     
# Fetch MLX-LM source from GitHub repository (optional: specify branch/tag with --branch)
ARG MLX_LM_REPO=https://github.com/ml-explore/mlx-lm.git
ARG MLX_LM_BRANCH=main
RUN git clone --depth 1 --branch ${MLX_LM_BRANCH} ${MLX_LM_REPO} /app/mlx-lm

# Install MLX-LM from source and required packages
RUN cd /app/mlx-lm && pip install -e .
RUN pip install fastapi uvicorn httpx litellm

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