---
layout: default
title: Conversations
nav_order: 2
description: "Full-stack LLM chat interfaces with multi-turn context preservation"
---

{% include table-of-contents.md %}

# Conversations Overview {#overview}

Raif provides full-stack (models, views, & controllers) LLM chat interface with multi-turn context preservation. 

If you use the `raif_conversation` view helper, it will automatically set up a chat interface that looks something like:

![Conversation Interface](../assets/images/screenshots/conversation-interface.png){:class="img-border"}

This feature utilizes Turbo Streams, Stimulus controllers, and ActiveJob, so your application must have those set up first. 

# Setup
First set up the css and javascript in your application. In the `<head>` section of your layout file:
```erb
<%= stylesheet_link_tag "raif" %>
```

In an app using import maps, add the following to your `application.js` file:
```js
import "raif"
```

In a controller serving the conversation view:
```ruby
class ExampleConversationController < ApplicationController
  def show
    @conversation = Raif::Conversation.where(creator: current_user).order(created_at: :desc).first

    if @conversation.nil?
      @conversation = Raif::Conversation.new(creator: current_user)
      @conversation.save!
    end
  end
end
```

And then in the view where you'd like to display the conversation interface:
```erb
<%= raif_conversation(@conversation) %>
```

By default, the conversation interface will use Bootstrap styles. If your app does not include Bootstrap, you can [override the views](customization#views) to update styles.

# Real-time Streaming Responses

Raif conversations include built-in support for streaming responses, where the LLM's response is displayed progressively as it's being generated.

Each time a conversation entry is updated during the streaming response, Raif will call `broadcast_replace_to(conversation)` (where `conversation` is the `Raif::Conversation` associated with the conversation entry). When using the `raif_conversation` view helper, it will automatically set up the Turbo Streams subscription for you.

## Streaming Chunk Size Configuration

By default, Raif will update the conversation entry's associated `Raif::ModelCompletion` and call `broadcast_replace_to(conversation)` after 25 characters have been accumuluated from the streaming response. If you want this to happen more or less frequently,
you can change the `streaming_chunk_size` configuration option in your initializer:

```ruby
Raif.configure do |config|
  config.streaming_chunk_size = 100
end
```

# Conversation Types

If your application involves different types of conversations, you can create a custom conversation types using the generator.

For example, say you are implementing a customer support chatbot in your application and want to a specialized system prompt and initial message for that conversation type:

```bash
rails generate raif:conversation CustomerSupport
```

This will create a new conversation type in `app/models/raif/conversations/customer_support.rb`.

You can then customize the system prompt, initial message, and available [model tools](model_tools) for that conversation type:

```ruby
class Raif::Conversations::CustomerSupport < Raif::Conversation
  before_create -> { 
    self.available_model_tools = [
      "Raif::ModelTools::SearchKnowledgeBase",
      "Raif::ModelTools::FileSupportTicket" 
    ]
  }

  def system_prompt_intro
    <<~PROMPT
      You are a helpful assistant who specializes in customer support. You're working with a customer who is experiencing an issue with your product.
    PROMPT
  end
  
  # The initial message is used to greet the user when the conversation is created.
  def initial_chat_message
    I18n.t("#{self.class.name.underscore.gsub("/", ".")}.initial_chat_message")
  end
end
```

# Tool Calling

If you set `available_model_tools` in your conversation, the LLM will be given the option to call those [tools](model_tools).

## Rendering Model Tool Invocations

## Providing Tool Observations/Results to the LLM