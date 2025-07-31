---
layout: default
title: Customization
nav_order: 6
description: "Customizing Raif for your application"
---

# Customization

## Controllers

You can override Raif's controllers by creating your own that inherit from Raif's base controllers:

```ruby
class ConversationsController < Raif::ConversationsController
  # Your customizations here
end

class ConversationEntriesController < Raif::ConversationEntriesController
  # Your customizations here
end
```

Then update the configuration:
```ruby
Raif.configure do |config|
  config.conversations_controller = "ConversationsController"
  config.conversation_entries_controller = "ConversationEntriesController"
end
```

## Models

By default, Raif models inherit from `ApplicationRecord`. You can change this:

```ruby
Raif.configure do |config|
  config.model_superclass = "CustomRecord"
end
```

## Views

You can customize Raif's views by copying them to your application and modifying them. To copy the conversation-related views, run:

```bash
rails generate raif:views
```

This will copy all conversation and conversation entry views to your application in:
- `app/views/raif/conversations/`
- `app/views/raif/conversation_entries/`

These views will automatically override Raif's default views. You can customize them to match your application's look and feel while maintaining the same functionality.

## System Prompts

If you don't want to override the system prompt entirely in your task/conversation subclasses, you can customize the intro portion of the system prompts for conversations and tasks:

```ruby
Raif.configure do |config|
  config.conversation_system_prompt_intro = "You are a helpful assistant who specializes in customer support."
  config.task_system_prompt_intro = "You are a helpful assistant who specializes in data analysis."
  # or with a lambda
  config.task_system_prompt_intro = ->(task) { "You are a helpful assistant who specializes in #{task.name}." }
  config.conversation_system_prompt_intro = ->(conversation) { "You are a helpful assistant talking to #{conversation.creator.email}. Today's date is #{Date.today.strftime('%B %d, %Y')}." }
end
```

## Adding LLM Models

You can easily add new LLM models to Raif:

```ruby
# Register the model in Raif's LLM registry
Raif.register_llm(Raif::Llms::OpenRouter, {
  key: :open_router_gemini_flash_1_5_8b, # a unique key for the model
  api_name: "google/gemini-flash-1.5-8b", # name of the model to be used in API calls - needs to match the provider's API name
  input_token_cost: 0.038 / 1_000_000, # the cost per input token
  output_token_cost: 0.15 / 1_000_000, # the cost per output token
})

# Then use the model
llm = Raif.llm(:open_router_gemini_flash_1_5_8b)
llm.chat(message: "Hello, world!")

# Or set it as the default LLM model in your initializer
Raif.configure do |config|
  config.default_llm_model_key = "open_router_gemini_flash_1_5_8b"
end
```