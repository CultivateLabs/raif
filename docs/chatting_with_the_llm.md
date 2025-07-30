---
layout: default
title: Chatting with the LLM
nav_order: 3
description: "Direct LLM interaction using Raif"
---

# Chatting with the LLM

When using Raif, it's often useful to use one of the [higher level abstractions](key_raif_concepts) in your application. But when needed, you can utilize `Raif::Llm` to chat with the model directly. All calls to the LLM will create and return a `Raif::ModelCompletion` record, providing you a log of all interactions with the LLM which can be viewed in the [web admin](web_admin).

Call `Raif::Llm#chat` with either a `message` string or `messages` array.:
```ruby
llm = Raif.llm(:open_ai_gpt_4o) # will return a Raif::Llm instance
model_completion = llm.chat(message: "Hello")
puts model_completion.raw_response
# => "Hello! How can I assist you today?"
```

The `Raif::ModelCompletion` class will handle parsing the response for you, should you ask for a different response format (which can be one of `:html`, `:text`, or `:json`). You can also provide a `system_prompt` to the `chat` method:
```ruby
llm = Raif.llm(:open_ai_gpt_4o)
messages = [
  { role: "user", content: "Hello" },
  { role: "assistant", content: "Hello! How can I assist you today?" },
  { role: "user", content: "Can you you tell me a joke?" },
]

system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object."

model_completion = llm.chat(messages: messages, response_format: :json, system_prompt: system_prompt)
puts model_completion.raw_response
# => ```json
# => {
# =>   "joke": "Why don't skeletons fight each other? They don't have the guts."
# => }
# => ```

puts model_completion.parsed_response # will strip backticks, parse the JSON, and give you a Ruby hash
# => {"joke" => "Why don't skeletons fight each other? They don't have the guts."}
```

## Streaming Responses

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