---
layout: default
title: Streaming Responses
nav_order: 3
description: "Streaming responses from the LLM"
---

# Streaming Responses

You can enable streaming for any chat call by passing a block to the `chat` method. When streaming is enabled, the block will be called with partial responses as they're received from the LLM. 

Streaming is enabled by default in [conversations](../key_raif_concepts/conversations).

```ruby
llm = Raif.llm(:open_ai_gpt_4o)
model_completion = llm.chat(message: "Tell me a story") do |model_completion, delta, sse_event|
  # This block is called multiple times as the response streams in.
  # You could broadcast these updates via Turbo Streams, WebSockets, etc.
  Turbo::StreamsChannel.broadcast_replace_to(
    :my_channel,
    target: "chat-response",
    partial: "my_partial_displaying_chat_response",
    locals: { model_completion: model_completion, delta: delta, sse_event: sse_event }
  )
end

# The final complete response is available in the model_completion
puts model_completion.raw_response
```

## Streaming Chunk Size Configuration

By default, Raif will update the `Raif::ModelCompletion` and call the block after 25 characters have been accumulated from the streaming response. If you want this to happen more or less frequently, you can change the `streaming_update_chunk_size_threshold` configuration option in your initializer:

```ruby
Raif.configure do |config|
  # Control how often the model completion is updated & the block is called when streaming.
  # Lower values = more frequent updates but more database writes.
  # Higher values = less frequent updates but fewer database writes.
  config.streaming_update_chunk_size_threshold = 50 # default is 25
end
```

## Unreliable Streaming Endpoints {#streaming-unsupported-model-keys}

Some provider + model combinations have streaming endpoints that are known to be unreliable — for example, Bedrock's Converse streaming API delivers corrupted/truncated `tool_use` deltas for the `openai.gpt-oss-*` models (the streamed chunks do not reconstruct to valid JSON even when the non-streaming path returns a well-formed tool call for the same prompt).

Raif maintains a list of model keys whose streaming path should be treated as broken via the `streaming_unsupported_model_keys` configuration option. When a caller passes a block to `Raif::Llm#chat` for a model key matching the list, Raif transparently falls back to the non-streaming path (the block is never invoked, and `ModelCompletion#stream_response` is `false` on the resulting record). This sidesteps provider streaming bugs without requiring callers to special-case them.

Each entry in the list may be a `String`, `Symbol`, or `Regexp` matched against the Raif model key:

```ruby
Raif.configure do |config|
  # Default — fences off both Bedrock gpt-oss-120b and gpt-oss-20b.
  config.streaming_unsupported_model_keys = [/\Abedrock_gpt_oss_/]

  # Add an individual model:
  config.streaming_unsupported_model_keys += [:some_other_broken_model]

  # Or disable the workaround entirely:
  config.streaming_unsupported_model_keys = []
end
```

### Diagnosing streaming issues

Two diagnostic scripts are shipped with Raif for investigating suspected streaming problems with a given model:

- `bin/probe_streaming_tool_calls` — runs the same tool-call prompt through one or more models in both streaming and non-streaming modes and reports per-model failure rates. Temporarily clears `streaming_unsupported_model_keys` so the streaming path is always exercised.
- `bin/probe_bedrock_stream_transport` — bypasses Raif entirely, hits Bedrock's Converse + ConverseStream APIs directly via the AWS SDK, and reports whether the reconstructed tool_use buffer is JSON-parseable. Useful for determining whether streaming corruption originates at the AWS service/SDK layer (below Raif's accumulator).

Both scripts print usage details when invoked without arguments.

---

**Read next:** [Images/Files/PDFs](images_files_pdfs)