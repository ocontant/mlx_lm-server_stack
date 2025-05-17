"""
Test script for Anthropic to OpenAI adapter

This script tests the Anthropic to OpenAI adapter by directly calling the adapter
functions with sample requests and checking the converted outputs.

Usage:
  python test_anthropic_adapter.py
"""

import json
import asyncio
from typing import Dict, Any

# Import the adapter
from anthropic_to_openai_adapter import AnthropicToOpenAIAdapter

# Create an instance of the adapter
adapter = AnthropicToOpenAIAdapter()

# Sample Anthropic request
SAMPLE_ANTHROPIC_REQUEST = {
    "model": "claude-3-sonnet-20240229",
    "max_tokens": 1024,
    "messages": [
        {"role": "user", "content": "Hello, world"}
    ],
    "system": "You are a helpful AI assistant.",
    "temperature": 0.7,
    "top_p": 0.9,
    "stream": False
}

# Sample Anthropic request with tools
SAMPLE_ANTHROPIC_TOOLS_REQUEST = {
    "model": "claude-3-sonnet-20240229",
    "max_tokens": 1024,
    "messages": [
        {"role": "user", "content": "What's the weather in San Francisco?"}
    ],
    "tools": [
        {
            "type": "function",
            "function": {
                "name": "get_weather",
                "description": "Get the current weather in a location",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "location": {
                            "type": "string",
                            "description": "The city and state, e.g. San Francisco, CA"
                        }
                    },
                    "required": ["location"]
                }
            }
        }
    ],
    "tool_choice": "auto",
    "stream": False
}

# Sample streaming request
SAMPLE_STREAMING_REQUEST = {
    "model": "claude-3-sonnet-20240229",
    "max_tokens": 1024,
    "messages": [
        {"role": "user", "content": "Hello, world"}
    ],
    "stream": True
}

# Sample OpenAI response
SAMPLE_OPENAI_RESPONSE = {
    "id": "chatcmpl-123",
    "object": "chat.completion",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "message": {
                "role": "assistant",
                "content": "Hello! How can I assist you today?"
            },
            "finish_reason": "stop",
            "index": 0
        }
    ],
    "usage": {
        "prompt_tokens": 15,
        "completion_tokens": 9,
        "total_tokens": 24
    }
}

# Sample OpenAI streaming chunk
SAMPLE_STREAMING_CHUNK = {
    "id": "chatcmpl-123",
    "object": "chat.completion.chunk",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "delta": {
                "content": "Hello"
            },
            "index": 0,
            "finish_reason": None
        }
    ]
}

# Sample completion streaming chunk
SAMPLE_COMPLETION_CHUNK = {
    "id": "chatcmpl-123",
    "object": "chat.completion.chunk",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "delta": {
                "role": "assistant"
            },
            "index": 0,
            "finish_reason": None
        }
    ]
}

# Sample final streaming chunk with finish_reason
SAMPLE_FINAL_CHUNK = {
    "id": "chatcmpl-123",
    "object": "chat.completion.chunk",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "delta": {},
            "index": 0,
            "finish_reason": "stop"
        }
    ]
}

# Sample tool call
SAMPLE_TOOL_RESPONSE = {
    "id": "chatcmpl-123",
    "object": "chat.completion",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "message": {
                "role": "assistant",
                "content": None,
                "tool_calls": [
                    {
                        "id": "call_abc123",
                        "function": {
                            "name": "get_weather",
                            "arguments": "{\"location\":\"San Francisco, CA\"}"
                        },
                        "type": "function"
                    }
                ]
            },
            "finish_reason": "tool_calls",
            "index": 0
        }
    ],
    "usage": {
        "prompt_tokens": 20,
        "completion_tokens": 12,
        "total_tokens": 32
    }
}

# Sample tool streaming chunk
SAMPLE_TOOL_STREAMING_CHUNK = {
    "id": "chatcmpl-123",
    "object": "chat.completion.chunk",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "delta": {
                "tool_calls": [
                    {
                        "index": 0,
                        "function": {
                            "name": "get_weather"
                        }
                    }
                ]
            },
            "index": 0,
            "finish_reason": None
        }
    ]
}

# Sample tool arguments streaming chunk
SAMPLE_TOOL_ARGS_CHUNK = {
    "id": "chatcmpl-123",
    "object": "chat.completion.chunk",
    "created": 1677858242,
    "model": "gpt-4o",
    "choices": [
        {
            "delta": {
                "tool_calls": [
                    {
                        "index": 0,
                        "function": {
                            "arguments": "{\"location\":"
                        }
                    }
                ]
            },
            "index": 0,
            "finish_reason": None
        }
    ]
}

def print_formatted_json(title: str, data: Dict[str, Any]) -> None:
    """Print formatted JSON with a title."""
    print(f"\n{title}:")
    print(json.dumps(data, indent=2))

def test_request_translation() -> None:
    """Test translation of request from Anthropic to OpenAI format."""
    print("\n======= TESTING REQUEST TRANSLATION =======")
    
    # Translate the request
    openai_request = adapter.translate_input(SAMPLE_ANTHROPIC_REQUEST)
    
    # Print original and translated request
    print_formatted_json("Original Anthropic Request", SAMPLE_ANTHROPIC_REQUEST)
    print_formatted_json("Translated OpenAI Request", openai_request)
    
    # Verify important conversions
    assert "messages" in openai_request, "Missing messages in translated request"
    assert openai_request["messages"][0]["role"] == "system", "System message not properly added"
    assert openai_request["max_tokens"] == 1024, "max_tokens not preserved"
    assert openai_request["temperature"] == 0.7, "temperature not preserved"
    assert openai_request["top_p"] == 0.9, "top_p not preserved"
    
    print("\n✅ Request translation test passed")

def test_tools_request_translation() -> None:
    """Test translation of request with tools from Anthropic to OpenAI format."""
    print("\n======= TESTING TOOLS REQUEST TRANSLATION =======")
    
    # Translate the request
    openai_request = adapter.translate_input(SAMPLE_ANTHROPIC_TOOLS_REQUEST)
    
    # Print original and translated request
    print_formatted_json("Original Anthropic Tools Request", SAMPLE_ANTHROPIC_TOOLS_REQUEST)
    print_formatted_json("Translated OpenAI Tools Request", openai_request)
    
    # Verify important conversions
    assert "tools" in openai_request, "Missing tools in translated request"
    assert openai_request["tools"][0]["type"] == "function", "Tool type not preserved"
    assert openai_request["tool_choice"] == "auto", "tool_choice not preserved"
    
    print("\n✅ Tools request translation test passed")

def test_response_translation() -> None:
    """Test translation of response from OpenAI to Anthropic format."""
    print("\n======= TESTING RESPONSE TRANSLATION =======")
    
    # Translate the response
    anthropic_response = adapter.translate_output(SAMPLE_OPENAI_RESPONSE, SAMPLE_ANTHROPIC_REQUEST)
    
    # Print original and translated response
    print_formatted_json("Original OpenAI Response", SAMPLE_OPENAI_RESPONSE)
    print_formatted_json("Translated Anthropic Response", anthropic_response)
    
    # Verify important conversions
    assert anthropic_response["type"] == "message", "Wrong response type"
    assert anthropic_response["role"] == "assistant", "Wrong role"
    assert anthropic_response["content"][0]["type"] == "text", "Content not properly formatted"
    assert anthropic_response["content"][0]["text"] == "Hello! How can I assist you today?", "Content not preserved"
    assert anthropic_response["stop_reason"] == "end_turn", "stop_reason not properly mapped"
    assert "usage" in anthropic_response, "Missing usage information"
    assert anthropic_response["usage"]["input_tokens"] == 15, "Input tokens not preserved"
    assert anthropic_response["usage"]["output_tokens"] == 9, "Output tokens not preserved"
    
    print("\n✅ Response translation test passed")

def test_tool_call_translation() -> None:
    """Test translation of tool calls from OpenAI to Anthropic format."""
    print("\n======= TESTING TOOL CALL TRANSLATION =======")
    
    # Translate the tool call response
    anthropic_response = adapter.translate_output(SAMPLE_TOOL_RESPONSE, SAMPLE_ANTHROPIC_REQUEST)
    
    # Print original and translated response
    print_formatted_json("Original OpenAI Tool Response", SAMPLE_TOOL_RESPONSE)
    print_formatted_json("Translated Anthropic Tool Response", anthropic_response)
    
    # Verify tool call conversions
    assert anthropic_response["type"] == "message", "Wrong response type"
    assert anthropic_response["content"][0]["type"] == "tool_use", "Tool use not properly formatted"
    assert anthropic_response["content"][0]["name"] == "get_weather", "Tool name not preserved"
    assert anthropic_response["content"][0]["input"]["location"] == "San Francisco, CA", "Tool arguments not properly parsed"
    assert anthropic_response["stop_reason"] == "tool_use", "stop_reason not properly mapped for tool calls"
    
    print("\n✅ Tool call translation test passed")

def test_streaming_chunk_translation() -> None:
    """Test translation of streaming chunks from OpenAI to Anthropic format."""
    print("\n======= TESTING STREAMING CHUNK TRANSLATION =======")
    
    # Reset streaming state
    adapter._sent_message_start = False
    
    # Test message_start when first chunk arrives
    completion_chunk = adapter.translate_streaming_chunk(SAMPLE_COMPLETION_CHUNK, SAMPLE_STREAMING_REQUEST)
    print_formatted_json("Translated message_start chunk", completion_chunk)
    assert completion_chunk["type"] == "message_start", "First chunk should be message_start"
    assert "message" in completion_chunk, "Missing message in message_start event"
    
    # Test content chunk
    content_chunk = adapter.translate_streaming_chunk(SAMPLE_STREAMING_CHUNK, SAMPLE_STREAMING_REQUEST)
    print_formatted_json("Original OpenAI Content Chunk", SAMPLE_STREAMING_CHUNK)
    print_formatted_json("Translated Content Chunk", content_chunk)
    assert content_chunk["type"] == "content_block_delta", "Wrong chunk type"
    assert content_chunk["delta"]["type"] == "text_delta", "Wrong delta type"
    assert content_chunk["delta"]["text"] == "Hello", "Text content not preserved"
    
    # Test final chunk with finish_reason
    final_chunk = adapter.translate_streaming_chunk(SAMPLE_FINAL_CHUNK, SAMPLE_STREAMING_REQUEST)
    print_formatted_json("Original OpenAI Final Chunk", SAMPLE_FINAL_CHUNK)
    print_formatted_json("Translated Final Chunk", final_chunk)
    assert final_chunk["type"] == "message_delta", "Wrong chunk type for final chunk"
    assert final_chunk["delta"]["stop_reason"] == "end_turn", "Wrong stop_reason in final chunk"
    
    print("\n✅ Streaming chunks translation test passed")

def test_tool_streaming_chunk_translation() -> None:
    """Test translation of tool streaming chunks from OpenAI to Anthropic format."""
    print("\n======= TESTING TOOL STREAMING CHUNK TRANSLATION =======")
    
    # Reset streaming state
    adapter._sent_message_start = False
    adapter._current_tool_calls = {}
    adapter._tool_call_index = 0
    adapter._content_index = 0
    
    # Test first message_start
    adapter.translate_streaming_chunk(SAMPLE_COMPLETION_CHUNK, SAMPLE_STREAMING_REQUEST)
    
    # Test tool name chunk
    tool_name_chunk = adapter.translate_streaming_chunk(SAMPLE_TOOL_STREAMING_CHUNK, SAMPLE_STREAMING_REQUEST)
    print_formatted_json("Original OpenAI Tool Name Chunk", SAMPLE_TOOL_STREAMING_CHUNK)
    print_formatted_json("Translated Tool Name Chunk", tool_name_chunk)
    assert tool_name_chunk["type"] == "content_block_delta", "Wrong chunk type"
    assert tool_name_chunk["delta"]["type"] == "tool_use_delta", "Wrong delta type"
    assert "name" in tool_name_chunk["delta"], "Missing name in tool_use_delta"
    
    # Test tool arguments chunk
    tool_args_chunk = adapter.translate_streaming_chunk(SAMPLE_TOOL_ARGS_CHUNK, SAMPLE_STREAMING_REQUEST)
    print_formatted_json("Original OpenAI Tool Args Chunk", SAMPLE_TOOL_ARGS_CHUNK)
    print_formatted_json("Translated Tool Args Chunk", tool_args_chunk)
    assert tool_args_chunk["type"] == "content_block_delta", "Wrong chunk type"
    assert tool_args_chunk["delta"]["type"] == "tool_use_delta", "Wrong delta type"
    assert "input_delta" in tool_args_chunk["delta"], "Missing input_delta in tool_use_delta"
    
    print("\n✅ Tool streaming chunks translation test passed")

async def test_async_processing() -> None:
    """Test async processing of streaming responses."""
    print("\n======= TESTING ASYNC PROCESSING =======")
    print("This test would normally use real streaming responses.")
    print("For unit testing purposes, we're just verifying the code structure.")
    
    # In a real test, we would mock the streaming response
    # Here we're just checking that the method exists and has the right signature
    assert hasattr(adapter, "process_streaming_response"), "Missing process_streaming_response method"
    
    print("\n✅ Async processing structure test passed")

if __name__ == "__main__":
    # Run the tests
    test_request_translation()
    test_tools_request_translation()
    test_response_translation()
    test_tool_call_translation()
    test_streaming_chunk_translation()
    test_tool_streaming_chunk_translation()
    
    # Run async test with event loop
    asyncio.run(test_async_processing())
    
    print("\n✅ All tests passed")