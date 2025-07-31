---
layout: default
title: Streaming Responses
nav_order: 2
description: "Streaming responses from the LLM"
---

# Streaming Responses

You can enable streaming for any chat call by passing a block to the `chat` method. When streaming is enabled, the block will be called with partial responses as they're received from the LLM:

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

You can configure the streaming update frequency by adjusting the chunk size threshold in your Raif configuration:

```ruby
Raif.configure do |config|
  # Control how often the model completion is updated & the block is called when streaming.
  # Lower values = more frequent updates but more database writes.
  # Higher values = less frequent updates but fewer database writes.
  config.streaming_update_chunk_size_threshold = 50 # default is 25
end
```