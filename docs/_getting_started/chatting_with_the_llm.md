---
layout: default
title: Chatting with the LLM
nav_order: 3
description: "Direct LLM interaction using Raif"
---

# Chatting with the LLM

When using Raif, you'll most often want to utilize the higher level abstractions like [Tasks](../key_raif_concepts/tasks), [Conversations](../key_raif_concepts/conversations), and [Agents](../key_raif_concepts/agents). But when needed, you can utilize the lower level `Raif::Llm` to chat with the model directly.

In Raif, **all** calls to the LLM generate a `Raif::ModelCompletion` record, providing you a log of all interactions with the LLM which can be viewed in the [web admin](../learn_more/web_admin).

Call `Raif::Llm#chat` with either a `message` string or `messages` array:
```ruby
llm = Raif.llm(:open_ai_gpt_4o) # will return a Raif::Llm instance
model_completion = llm.chat(message: "Hello")
puts model_completion.raw_response
# => "Hello! How can I assist you today?"
```

The `Raif::ModelCompletion` class will handle parsing the response for you, should you ask for a different response format (which can be `:html`, `:text`, or `:json`). 

You can also provide a `system_prompt` to the `chat` method:
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

