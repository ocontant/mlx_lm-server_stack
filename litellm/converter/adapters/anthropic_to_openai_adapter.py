"""
Anthropic to OpenAI adapter for LiteLLM proxy

This adapter converts requests in Anthropic Messages API format to OpenAI Chat Completions
format and vice versa, allowing Anthropic client libraries to work with OpenAI-compatible
models including local models through LM Studio.

Features:
- Request format conversion (Anthropic → OpenAI)
- Response format conversion (OpenAI → Anthropic)
- Streaming support
- System message handling
- Error format conversion
"""

import json
import asyncio
import time
from typing import Any, AsyncIterator, Dict, List, Optional, Union, cast, TypeVar

# Type variable for anything that supports the async iterator protocol
T_AsyncIterable = TypeVar('T_AsyncIterable', bound=Any)

import httpx
import litellm
from litellm import ModelResponse
from litellm.integrations.custom_logger import CustomLogger
from pydantic import BaseModel


class AnthropicToOpenAIAdapter(CustomLogger):
    def __init__(self) -> None:
        super().__init__()
        self.provider = "openai"  # Target provider
        self._sent_message_start = False
        self._current_tool_calls = {}  # Track tool calls state across chunks
        self._tool_call_index = 0  # Current tool call index
        self._content_index = 0    # Current content block index
    
    def translate_input(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert Anthropic Messages API format to OpenAI Chat Completions format
        """
        # Extract common parameters
        model = request_data.get("model", "")
        messages = request_data.get("messages", [])
        max_tokens = request_data.get("max_tokens", 1024)
        temperature = request_data.get("temperature", 0.7)
        stream = request_data.get("stream", False)
        
        # Convert any Anthropic-specific parameters
        openai_request = {
            "model": model,
            "messages": messages.copy(),  # Copy to avoid modifying the original
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": stream,
        }
        
        # Add system message if provided in Anthropic format (outside messages)
        if "system" in request_data:
            system_message = {"role": "system", "content": request_data["system"]}
            openai_request["messages"].insert(0, system_message)
        
        # Handle tool calling if present
        if "tools" in request_data:
            openai_request["tools"] = request_data["tools"]
            
        if "tool_choice" in request_data:
            openai_request["tool_choice"] = request_data["tool_choice"]
        
        # Add any Anthropic stop sequences as OpenAI stop
        if "stop_sequences" in request_data:
            openai_request["stop"] = request_data["stop_sequences"]
        
        # Add top_p if provided
        if "top_p" in request_data:
            openai_request["top_p"] = request_data["top_p"]
        
        # Handle additional parameters that LiteLLM might need
        if "litellm_metadata" in request_data:
            openai_request["litellm_metadata"] = request_data["litellm_metadata"]
            
        # Map Anthropic 'top_k' to OpenAI 'top_k' if the provider supports it
        if "top_k" in request_data:
            openai_request["top_k"] = request_data["top_k"]
        
        # Preserve any metadata for LiteLLM internal use
        if "metadata" in request_data:
            if "litellm_metadata" not in openai_request:
                openai_request["litellm_metadata"] = {}
            openai_request["litellm_metadata"]["anthropic_metadata"] = request_data["metadata"]
        
        return openai_request
    
    def translate_output(self, response: Any, original_request: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert OpenAI response format to Anthropic response format
        
        Takes an OpenAI-formatted response and converts it to Anthropic's Messages API format,
        handling both text content and tool calls.
        """
        # Handle different response types
        if isinstance(response, dict):  
            # Already a dict (e.g., from streaming)
            openai_response = response
        elif hasattr(response, "model_dump"):
            # If it supports Pydantic v2 model_dump
            openai_response = response.model_dump()
        elif hasattr(response, "dict"):
            # If it supports Pydantic v1 dict
            openai_response = response.dict()
        elif hasattr(response, "json"):
            # If it has a json method (like ModelResponse)
            openai_response = response.json()
        else:
            # Last resort, convert to string and make a simple response
            openai_response = {
                "id": f"msg_{int(time.time())}",
                "choices": [
                    {
                        "message": {
                            "content": str(response)
                        },
                        "finish_reason": "stop"
                    }
                ]
            }
        
        # Build base Anthropic response structure
        anthropic_response = {
            "id": openai_response.get("id", f"msg_{int(time.time())}"),
            "type": "message",
            "role": "assistant",
            "model": original_request.get("model", ""),
            "stop_reason": None,
            "stop_sequence": None,
            "usage": {
                "input_tokens": 0,
                "output_tokens": 0,
            }
        }
        
        # Extract content from OpenAI response
        if "choices" in openai_response:
            choice = openai_response["choices"][0]
            
            # Get the finish reason and map it to Anthropic format
            finish_reason = choice.get("finish_reason", None)
            if finish_reason == "stop":
                anthropic_response["stop_reason"] = "end_turn"
            elif finish_reason == "length":
                anthropic_response["stop_reason"] = "max_tokens"
            elif finish_reason == "content_filter":
                anthropic_response["stop_reason"] = "stop_sequence"
                anthropic_response["stop_sequence"] = "<content_filter>"
            elif finish_reason == "tool_calls":
                anthropic_response["stop_reason"] = "tool_use"
            else:
                anthropic_response["stop_reason"] = finish_reason
            
            # Handle different response formats
            message = choice.get("message", {})
            content = message.get("content", "")
            
            # Initialize content array
            anthropic_response["content"] = []
            
            # Add text content if present
            if content is not None and content != "":
                anthropic_response["content"].append({"type": "text", "text": content})
                
            # Handle tool calls if present
            if "tool_calls" in message and message["tool_calls"]:
                for tool_call in message["tool_calls"]:
                    function = tool_call.get("function", {})
                    
                    # Try to parse JSON arguments
                    try:
                        input_data = json.loads(function.get("arguments", "{}"))
                    except json.JSONDecodeError:
                        # Fallback if JSON parsing fails
                        input_data = {"raw": function.get("arguments", "")}
                    
                    anthropic_response["content"].append({
                        "type": "tool_use",
                        "id": tool_call.get("id", f"call_{int(time.time())}"),
                        "name": function.get("name", ""),
                        "input": input_data,
                    })
        
        # Copy usage information if available
        if "usage" in openai_response:
            usage = openai_response["usage"]
            anthropic_response["usage"]["input_tokens"] = usage.get("prompt_tokens", 0)
            anthropic_response["usage"]["output_tokens"] = usage.get("completion_tokens", 0)
        
        return anthropic_response
    
    def translate_streaming_chunk(self, chunk: Dict[str, Any], request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert a single OpenAI streaming chunk to Anthropic streaming format
        
        Handles stateful processing of streaming chunks, particularly for tool calls
        which may be split across multiple chunks.
        """
        if "choices" not in chunk:
            # Handle non-content chunks (like [DONE])
            if chunk.get("id", "") == "[DONE]":
                return {"type": "message_stop"}
            return chunk

        choice = chunk["choices"][0]
        delta = choice.get("delta", {})
        
        # First chunk handling - send message_start
        if not self._sent_message_start and (chunk.get("created") or "role" in delta):
            message_id = chunk.get("id", f"msg_{int(time.time())}")
            self._sent_message_start = True
            return {
                "type": "message_start",
                "message": {
                    "id": message_id,
                    "type": "message",
                    "role": "assistant",
                    "content": [],
                    "model": request_data.get("model", ""),
                }
            }
        
        # Check what type of content is in this chunk
        if "content" in delta and delta["content"]:
            # Standard text content
            return {
                "type": "content_block_delta",
                "index": self._content_index,
                "delta": {
                    "type": "text_delta",
                    "text": delta["content"]
                }
            }
        elif "tool_calls" in delta:
            # Tool call content - requires stateful handling
            tool_calls = delta["tool_calls"]
            
            for tool_call in tool_calls:
                tool_call_id = tool_call.get("index", 0)
                
                # Initialize tool call state if this is a new one
                if tool_call_id not in self._current_tool_calls:
                    self._current_tool_calls[tool_call_id] = {
                        "id": tool_call.get("id", f"call_{tool_call_id}"),
                        "name": "",
                        "arguments": ""
                    }
                    self._tool_call_index = self._content_index + 1
                    self._content_index += 1  # Increment for each new tool call
                
                # Update tool call state
                if "function" in tool_call:
                    function_data = tool_call["function"]
                    current_state = self._current_tool_calls[tool_call_id]
                    
                    # Update name if present
                    if "name" in function_data:
                        current_state["name"] = function_data["name"]
                    
                    # Accumulate arguments if present
                    if "arguments" in function_data:
                        current_state["arguments"] += function_data["arguments"]
                    
                    # Return appropriate delta
                    if function_data.get("name"):
                        return {
                            "type": "content_block_delta",
                            "index": self._tool_call_index,
                            "delta": {
                                "type": "tool_use_delta",
                                "id": current_state["id"],
                                "name": function_data.get("name", "")
                            }
                        }
                    elif function_data.get("arguments"):
                        return {
                            "type": "content_block_delta",
                            "index": self._tool_call_index,
                            "delta": {
                                "type": "tool_use_delta",
                                "input_delta": function_data.get("arguments", "")
                            }
                        }
            
            # Fallback for empty tool call delta
            return {
                "type": "content_block_delta",
                "index": self._tool_call_index,
                "delta": {
                    "type": "tool_use_delta",
                    "input_delta": ""
                }
            }
        elif choice.get("finish_reason") is not None:
            # Final chunk with finish reason
            finish_reason = choice.get("finish_reason")
            stop_reason = "end_turn" if finish_reason == "stop" else finish_reason
            
            # Reset state variables for next stream
            self._current_tool_calls = {}
            self._tool_call_index = 0
            self._content_index = 0
            
            return {
                "type": "message_delta",
                "delta": {
                    "stop_reason": stop_reason
                }
            }
        else:
            # Empty content chunk or unhandled type
            return {
                "type": "content_block_delta",
                "index": self._content_index,
                "delta": {
                    "type": "text_delta",
                    "text": ""
                }
            }
    
    async def process_streaming_response(self, 
                                         stream_response: Any, 
                                         request_data: Dict[str, Any]) -> AsyncIterator[str]:
        """
        Process a streaming response into Anthropic's streaming format
        
        This method handles various types of streaming responses from different providers,
        ensuring they are converted to Anthropic's expected Server-Sent Events format.
        
        Handles stateful conversion of streaming chunks, including proper tracking for tool calls
        and ensuring all required SSE events are sent according to Anthropic's protocol.
        
        Args:
            stream_response: An async iterator or similar object yielding streaming response chunks
            request_data: The original request data to provide context for the conversion
            
        Returns:
            An async iterator yielding Anthropic-formatted SSE chunks
        """
        # Reset state for the new streaming session
        self._sent_message_start = False
        self._current_tool_calls = {}
        self._tool_call_index = 0
        self._content_index = 0
        
        try:
            # Different types of responses from litellm.acompletion might be returned
            # We need to handle ModelResponse, CustomStreamWrapper, or other types
            
            # If it's an async iterator-like object (has __aiter__)
            if hasattr(stream_response, "__aiter__") and callable(stream_response.__aiter__):
                try:
                    # Cast the stream_response to AsyncIterator to satisfy Pylance
                    # This tells the type checker that this object supports the async iterator protocol
                    iterator = cast(AsyncIterator[Any], stream_response)
                    
                    # Now we can use async for with the cast object
                    async for chunk in iterator:
                        # Convert the chunk data format
                        if hasattr(chunk, "model_dump"):
                            chunk_data = chunk.model_dump()
                        elif hasattr(chunk, "dict"):
                            chunk_data = chunk.dict()
                        elif isinstance(chunk, str):
                            # Handle string chunks (e.g., raw SSE lines)
                            try:
                                # Try to parse as JSON if the string starts with "data: "
                                if chunk.startswith("data: "):
                                    json_str = chunk[6:].strip()
                                    if json_str == "[DONE]":
                                        # Special case for OpenAI [DONE] marker
                                        chunk_data = {"id": "[DONE]"}
                                    else:
                                        chunk_data = json.loads(json_str)
                                else:
                                    # Treat as raw content
                                    chunk_data = {"choices": [{"delta": {"content": chunk}}]}
                            except json.JSONDecodeError:
                                # If JSON parsing fails, treat as raw content
                                chunk_data = {"choices": [{"delta": {"content": chunk}}]}
                        else:
                            # For other types, just use as is
                            chunk_data = chunk
                            
                        # Convert to Anthropic streaming format
                        anthropic_chunk = self.translate_streaming_chunk(chunk_data, request_data)
                        
                        # Convert to the expected SSE format
                        if isinstance(anthropic_chunk, dict):
                            yield f"data: {json.dumps(anthropic_chunk)}\n\n"
                        else:
                            yield f"data: {anthropic_chunk}\n\n"
                except (TypeError, AttributeError):
                    # If async iteration fails, treat it as a non-iteratable response
                    # Fall through to the non-iterator handling below
                    pass
                except Exception as e:
                    # For other errors during iteration, yield an error
                    error_chunk = {
                        "type": "error",
                        "error": {
                            "type": "server_error",
                            "message": f"Streaming error: {str(e)}"
                        }
                    }
                    yield f"data: {json.dumps(error_chunk)}\n\n"
                    # Continue with normal flow for cleanup in finally block
                    return
            
            # If it has iter_lines method (like httpx.Response)
            elif hasattr(stream_response, "iter_lines") and callable(stream_response.iter_lines):
                try:
                    # Get the iterator and cast it to satisfy type checking
                    # This tells Pylance to treat it as something that supports the async iterator protocol
                    lines_iterator = cast(AsyncIterator[bytes], stream_response.iter_lines())
                    
                    # Now we can use async for with the cast object
                    async for line in lines_iterator:
                        # Process each line
                        if isinstance(line, bytes):
                            line = line.decode('utf-8')
                        
                        if not line or line.isspace():
                            continue
                            
                        # Try to parse as JSON if it looks like SSE
                        if line.startswith("data: "):
                            data = line[6:].strip()
                            if data == "[DONE]":
                                continue  # We'll send our own DONE marker at the end
                            try:
                                chunk_data = json.loads(data)
                            except json.JSONDecodeError:
                                chunk_data = {"choices": [{"delta": {"content": data}}]}
                        else:
                            chunk_data = {"choices": [{"delta": {"content": line}}]}
                        
                        # Convert to Anthropic streaming format
                        anthropic_chunk = self.translate_streaming_chunk(chunk_data, request_data)
                        
                        # Yield in SSE format
                        if isinstance(anthropic_chunk, dict):
                            yield f"data: {json.dumps(anthropic_chunk)}\n\n"
                        else:
                            yield f"data: {anthropic_chunk}\n\n"
                except (TypeError, AttributeError):
                    # If iteration fails, fall through to the non-iterator handling
                    pass
                except Exception as e:
                    # For other errors during iteration, yield an error
                    error_chunk = {
                        "type": "error",
                        "error": {
                            "type": "server_error",
                            "message": f"Streaming error: {str(e)}"
                        }
                    }
                    yield f"data: {json.dumps(error_chunk)}\n\n"
                    # Continue with normal flow for cleanup in finally block
                    return
            
            # If it's a ModelResponse or similar without iteration support
            else:
                # Create a single chunk with all content
                if hasattr(stream_response, "model_dump"):
                    response_data = stream_response.model_dump() 
                elif hasattr(stream_response, "dict"):
                    response_data = stream_response.dict()
                else:
                    # Try to convert to a dict if possible
                    response_data = {"choices": [{"message": {"content": str(stream_response)}}]}
                
                # Send as standard response rather than streaming
                # First send message_start
                message_start = {
                    "type": "message_start",
                    "message": {
                        "id": response_data.get("id", f"msg_{int(time.time())}"),
                        "type": "message",
                        "role": "assistant",
                        "content": [],
                        "model": request_data.get("model", ""),
                    }
                }
                yield f"data: {json.dumps(message_start)}\n\n"
                self._sent_message_start = True
                
                # Extract content
                content = ""
                if "choices" in response_data and response_data["choices"]:
                    message = response_data["choices"][0].get("message", {})
                    if isinstance(message, dict):
                        content = message.get("content", "")
                
                # Send content block
                if content:
                    content_block = {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {
                            "type": "text_delta",
                            "text": content
                        }
                    }
                    yield f"data: {json.dumps(content_block)}\n\n"
                
                # Send message_delta with stop_reason
                message_delta = {
                    "type": "message_delta",
                    "delta": {
                        "stop_reason": "end_turn"
                    }
                }
                yield f"data: {json.dumps(message_delta)}\n\n"
                
        except Exception as e:
            # Send error in Anthropic format
            error_chunk = {
                "type": "error",
                "error": {
                    "type": "server_error",
                    "message": str(e)
                }
            }
            yield f"data: {json.dumps(error_chunk)}\n\n"
        finally:
            # Ensure we send a final message_stop event if it hasn't been sent already
            if self._sent_message_start:
                yield f"data: {json.dumps({'type': 'message_stop'})}\n\n"
            
            # This is for clients expecting the OpenAI-style [DONE] marker
            yield "data: [DONE]\n\n"
            
            # Clean up state
            self._sent_message_start = False
            self._current_tool_calls = {}
            self._tool_call_index = 0
            self._content_index = 0
    
    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        """
        Process the request and response for the passthrough endpoint
        This method is called by LiteLLM's passthrough endpoint handler
        
        Note: This implementation processes Anthropic API requests through OpenAI format
        and stores the converted response in response_obj.converted_response for the proxy
        to use. The method itself returns None to comply with CustomLogger's interface.
        """
        try:
            # Convert input from Anthropic to OpenAI format
            openai_request = self.translate_input(kwargs)
            
            # Store the converted request if needed
            response_obj.converted_request = openai_request
            
            # Handle streaming requests differently
            if openai_request.get("stream", False):
                # For streaming, we need to get the streaming response and process it
                stream_response = await litellm.acompletion(**openai_request)
                
                # Store a reference to the original stream response in case needed
                if hasattr(response_obj, "raw_response"):
                    response_obj.raw_response = stream_response
                
                # All we need to do is process the stream response - no matter what type it is
                # process_streaming_response is designed to handle any kind of response
                streaming_processor = self.process_streaming_response(stream_response, kwargs)
                
                # Store the streaming processor for the proxy to use
                response_obj.converted_response = streaming_processor
            else:
                # For non-streaming, make the call and translate the response
                response = await litellm.acompletion(**openai_request)
                anthropic_response = self.translate_output(response, kwargs)
                # Store the converted response for the proxy to use
                response_obj.converted_response = anthropic_response
                
        except Exception as e:
            # Convert error to Anthropic format
            error_response = {
                "type": "error",
                "error": {
                    "type": "invalid_request_error",
                    "message": str(e)
                }
            }
            # Store the error response for the proxy to use
            response_obj.converted_response = error_response
            
        # Return None to comply with CustomLogger interface
        return None

    # Required for CustomLogger compatibility
    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        """
        Synchronous version of async_log_success_event
        """
        raise NotImplementedError("Use async_log_success_event instead for this adapter")

    def log_failure_event(self, kwargs, response_obj, start_time, end_time):
        """
        Process errors - convert from OpenAI error format to Anthropic error format
        
        Note: This implementation converts errors to Anthropic format and stores the
        result in response_obj.converted_response for the proxy to use. The method 
        itself returns None to comply with CustomLogger's interface.
        """
        error_message = str(response_obj)
        error_type = "invalid_request_error"
        
        # Try to extract more detailed error information
        if hasattr(response_obj, "json"):
            try:
                error_data = response_obj.json()
                if "error" in error_data:
                    error_message = error_data["error"].get("message", error_message)
                    error_type = error_data["error"].get("type", error_type)
            except:
                pass
        
        # Create error in Anthropic format
        anthropic_error = {
            "type": "error",
            "error": {
                "type": error_type,
                "message": error_message
            }
        }
        
        # Store the error response for the proxy to use
        if hasattr(response_obj, "converted_response"):
            response_obj.converted_response = anthropic_error
        else:
            # For cases where response_obj doesn't have the attribute,
            # we'll attach it dynamically
            setattr(response_obj, "converted_response", anthropic_error)
            
        # Return None to comply with CustomLogger interface
        return None


# Create an instance of the adapter
anthropic_to_openai_adapter = AnthropicToOpenAIAdapter()