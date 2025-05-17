# Anthropic to OpenAI Adapter

This adapter converts between Anthropic's Messages API format and OpenAI's Chat Completions format. It enables you to:

1. Use OpenAI-compatible models to respond to requests in Anthropic's format
2. Connect Anthropic clients to OpenAI-compatible APIs 
3. Support local models through tools like LM Studio that offer OpenAI-compatible endpoints

## Features

- Full conversion between Anthropic/OpenAI formats
- Support for streaming responses
- Tool calling support
- System message handling
- Error format conversion

## Usage

There are two main ways to use this adapter:

### 1. In Router Configuration (Recommended)

```yaml
# In your litellm config.yaml
model_list:
  - model_name: claude-3-7-sonnet-20250219
    litellm_params:
      model: lm_studio/llama3-8b  # Or any OpenAI-compatible model
      api_base: http://localhost:1234/v1  # Your OpenAI-compatible endpoint
      api_key: not-needed  # Can be a dummy value for local servers
      use_in_pass_through: true

router_settings:
  pass_through_endpoints:
    anthropic:
      target_adapter: litellm.llms.anthropic.converter.adapters.anthropic_to_openai_adapter

pass_through_credentials:
  anthropic:
    api_key: not-needed  # Required even for local models
```

### 2. Registering the Adapter Programmatically

```python
from litellm.proxy.pass_through_endpoints.llm_passthrough_endpoints import register_pass_through_endpoint
from litellm.llms.anthropic.converter.adapters import anthropic_to_openai_adapter

# Register the adapter
register_pass_through_endpoint(provider="anthropic", target=anthropic_to_openai_adapter)
```

## Docker Configuration

If you're using Docker, you'll need to make sure the adapter files are accessible. Add this to your Dockerfile:

```Dockerfile
# Copy the adapter files
COPY litellm/llms/anthropic/converter /app/litellm/llms/anthropic/converter
```

## Troubleshooting

### Common Issues

1. **"No deployments available for selected model"**:
   - Ensure your model_name in configuration exactly matches what clients are requesting
   - Check that the route to your local model is accessible (e.g., http://host.docker.internal:11433 for Docker)

2. **"api_key is required for setting pass-through credentials"**:
   - Even for local models, you need to specify an api_key (can be a dummy value like "not-needed")
   - Make sure to set it in both the model configuration and pass_through_credentials

3. **Adapter not found**:
   - Ensure the path to the adapter is correct in your configuration
   - For Docker, make sure the adapter files are properly copied into the container

## Debugging Tips

1. Check the model_name in both your configuration and client request
2. Ensure the OpenAI-compatible API endpoint is reachable
3. Verify all required credentials are specified
4. Look for any errors in the log related to the adapter loading