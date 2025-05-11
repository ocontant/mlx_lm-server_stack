#!/bin/bash

# Default values if environment variables not set
MLX_HOST=${MLX_HOST:-0.0.0.0}
MLX_PORT=${MLX_PORT:-11432}
MLX_MODEL=${MLX_MODEL:-mlx-community/Qwen2.5-Coder-32B-Instruct-8bit}
LOG_LEVEL=${LOG_LEVEL:-INFO}

echo "Starting MLX-LM server with model: ${MLX_MODEL}"
echo "Listening on: ${MLX_HOST}:${MLX_PORT}"
echo "Log level: ${LOG_LEVEL}"

# Start the MLX-LM server
exec python3 -m mlx_lm.server \
  --model "${MLX_MODEL}" \
  --host "${MLX_HOST}" \
  --port "${MLX_PORT}" \
  --log-level "${LOG_LEVEL}"