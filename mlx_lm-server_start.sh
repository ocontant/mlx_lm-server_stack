#!/bin/bash

# Default values if environment variables not set
MLX_HOST=${MLX_HOST:-0.0.0.0}
MLX_PORT=${MLX_PORT:-11432}
MLX_MODEL=${MLX_MODEL:-mlx-community/Qwen2.5-Coder-32B-Instruct-8bit}
LOG_LEVEL=${LOG_LEVEL:-INFO}
TRUST_REMOTE_CODE=${TRUST_REMOTE_CODE:-false}
EOS_TOKEN=${EOS_TOKEN:-""}
EXTRA_ARGS=${EXTRA_ARGS:-""}

echo "Starting MLX-LM server with model: ${MLX_MODEL}"
echo "Listening on: ${MLX_HOST}:${MLX_PORT}"
echo "Log level: ${LOG_LEVEL}"

# Initialize additional arguments
ADDITIONAL_ARGS=""

# Check if we need to handle special model requirements
if [[ "$TRUST_REMOTE_CODE" == "true" ]]; then
  echo "Enabling trust_remote_code for model"
  ADDITIONAL_ARGS="${ADDITIONAL_ARGS} --trust-remote-code"
fi

# Add EOS token if specified
if [[ -n "$EOS_TOKEN" ]]; then
  echo "Setting custom EOS token: ${EOS_TOKEN}"
  ADDITIONAL_ARGS="${ADDITIONAL_ARGS} --eos-token \"${EOS_TOKEN}\""
fi

# Add any extra args
if [[ -n "$EXTRA_ARGS" ]]; then
  echo "Adding extra arguments: ${EXTRA_ARGS}"
  ADDITIONAL_ARGS="${ADDITIONAL_ARGS} ${EXTRA_ARGS}"
fi

# Model-specific configurations based on name patterns
if [[ "$MLX_MODEL" == *"qwen"* ]] || [[ "$MLX_MODEL" == *"Qwen"* ]]; then
  echo "Detected Qwen model - enabling required settings"
  if [[ "$TRUST_REMOTE_CODE" != "true" ]]; then
    echo "Enabling trust_remote_code for Qwen model"
    ADDITIONAL_ARGS="${ADDITIONAL_ARGS} --trust-remote-code"
  fi

  if [[ -z "$EOS_TOKEN" ]]; then
    echo "Setting default EOS token for Qwen model"
    ADDITIONAL_ARGS="${ADDITIONAL_ARGS} --eos-token \"<|endoftext|>\""
  fi
fi

if [[ "$MLX_MODEL" == *"plamo"* ]]; then
  echo "Detected Plamo model - enabling required settings"
  if [[ "$TRUST_REMOTE_CODE" != "true" ]]; then
    echo "Enabling trust_remote_code for Plamo model"
    ADDITIONAL_ARGS="${ADDITIONAL_ARGS} --trust-remote-code"
  fi
fi

echo "Starting server with additional args: ${ADDITIONAL_ARGS}"

# Start the MLX-LM server with eval to properly handle quoted arguments
eval "exec python3 -m mlx_lm.server \
  --model \"${MLX_MODEL}\" \
  --host \"${MLX_HOST}\" \
  --port \"${MLX_PORT}\" \
  --log-level \"${LOG_LEVEL}\" \
  ${ADDITIONAL_ARGS}"