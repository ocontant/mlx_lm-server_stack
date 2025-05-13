# Model Configuration Guide

This document explains how different model families are configured in the MLX-LM server to support their specific requirements.

## Model-Specific Parameters

Some model families require special configuration to work properly. The system supports:

1. **Automatic configuration** based on model name patterns
2. **Command-line parameters** for explicit configuration
3. **API request parameters** for dynamic loading

## Supported Model Families

| Model Family | Requirements | Config Applied |
|--------------|--------------|---------------|
| **Qwen** | trust_remote_code=True<br>eos_token="<\|endoftext\|>" | Applied automatically for names containing "qwen" or "Qwen" |
| **Plamo** | trust_remote_code=True | Applied automatically for names containing "plamo" |
| **InternLM** | trust_remote_code=True | Applied automatically for names containing "internlm" |
| **Yi** | trust_remote_code=True | Applied automatically for names containing "yi" |

## Using Model-Specific Parameters

### Command Line

```bash
# For Qwen models
mlx_lm.server --model Qwen/Qwen-7B --trust-remote-code --eos-token "<|endoftext|>"

# For Plamo models
mlx_lm.server --model pfnet/plamo-13b --trust-remote-code
```

### Docker Environment Variables

```bash
# For Qwen models
MLX_MODEL=Qwen/Qwen-7B TRUST_REMOTE_CODE=true EOS_TOKEN="<|endoftext|>" docker-compose up -d

# For other models that need trust_remote_code
MLX_MODEL=pfnet/plamo-13b TRUST_REMOTE_CODE=true docker-compose up -d
```

### API Requests

When making API requests, you can include tokenizer parameters:

```json
{
  "model": "Qwen/Qwen-7B",
  "prompt": "Hello, how are you?",
  "tokenizer_params": {
    "trust_remote_code": true,
    "eos_token": "<|endoftext|>"
  }
}
```

## Adding Support for New Model Families

To add support for a new model family with specific requirements:

1. Update `model_configs.py` with the new pattern and requirements:

```python
MODEL_FAMILY_CONFIGS = {
    # Existing configs...
    
    # New model family
    r"new-model-pattern": {
        "trust_remote_code": True,
        "special_param": "value"
    }
}
```

The pattern is a regular expression that will be matched against the model name with `re.search()`.

## Implementation Details

The parameter injection happens in the `ModelProvider.load()` method in `server.py`, which:

1. Determines the actual model name
2. Looks up model-specific configurations
3. Applies configurations from CLI arguments
4. Applies model-specific configurations
5. Applies request-specific parameters
6. Cleans up the configuration by removing None values
7. Loads the model with the resulting configuration

This design ensures that all necessary model-specific parameters are applied automatically without requiring manual configuration for each supported model family.