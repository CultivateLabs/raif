---
layout: default
title: Conversations
nav_order: 4
description: "Multi-turn chat interfaces with LLMs"
---

# Conversations
{: .no_toc }

Multi-turn chat interfaces with Large Language Models for interactive AI assistants and chatbots.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Conversations provide structured multi-turn chat experiences with LLMs, maintaining context across exchanges.

### Key Features
- **Persistent Context**: Maintains conversation history
- **Multiple LLM Support**: Works with OpenAI, Anthropic, AWS Bedrock, and more
- **Tool Integration**: Can invoke custom model tools during conversations
- **Real-time Updates**: Built-in Turbo Streams support

---

## Creating a Conversation

```bash
rails generate raif:conversation CustomerSupport
```

```ruby
class Raif::Conversations::CustomerSupport < Raif::ApplicationConversation
  llm_response_format :html
  
  before_create -> { 
    self.available_model_tools = [
      "Raif::ModelTools::ProviderManaged::WebSearch",
      "Raif::ModelTools::WikipediaSearch"
    ]
  }
  
  def build_system_prompt
    <<~PROMPT
      You are a helpful customer support assistant for our SaaS product.
      
      Guidelines:
      - Be friendly and professional
      - Ask clarifying questions when needed
      - Provide specific, actionable solutions
    PROMPT
  end
  
  # Optional: Custom processing of AI responses
  def process_model_response_message(message:, entry:)
    message.gsub(/inappropriate_word/, '[FILTERED]')
  end
end
```

---

## Usage

### Starting a Conversation

```ruby
# Create conversation
conversation = Raif::Conversations::CustomerSupport.create!(
  creator: current_user
)

# Add user message
entry = conversation.entries.create!(
  user_message: "I'm having trouble logging into my account",
  creator: current_user
)

# Process to get AI response
entry.process_entry!

puts entry.model_response_message
# => "I'd be happy to help you with your login issue..."
```

### Continuing the Conversation

```ruby
# Add follow-up message
entry = conversation.entries.create!(
  user_message: "I keep getting an 'invalid password' error",
  creator: current_user
)

entry.process_entry!
puts entry.model_response_message
```

### Accessing History

```ruby
# Get all entries in order
entries = conversation.entries.oldest_first

entries.each do |entry|
  puts "User: #{entry.user_message}" if entry.user_message.present?
  puts "AI: #{entry.model_response_message}" if entry.model_response_message.present?
end
```

---

## Controller Integration

```ruby
class ChatController < ApplicationController
  before_action :authenticate_user!
  
  def show
    @conversation = find_or_create_conversation
  end
  
  def create_entry
    @conversation = Raif::Conversation.find(params[:conversation_id])
    
    @entry = @conversation.entries.build(entry_params)
    @entry.creator = current_user
    
    if @entry.save
      # Process asynchronously for better UX
      Raif::ConversationEntryJob.perform_later(conversation_entry: @entry)
      render json: { status: 'processing', entry_id: @entry.id }
    else
      render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  private
  
  def find_or_create_conversation
    if session[:conversation_id]
      Raif::Conversations::CustomerSupport.find(session[:conversation_id])
    else
      conversation = Raif::Conversations::CustomerSupport.create!(creator: current_user)
      session[:conversation_id] = conversation.id
      conversation
    end
  end
  
  def entry_params
    params.require(:entry).permit(:user_message)
  end
end
```

---

## Real-time Updates

Enable real-time conversation updates with Turbo Streams:

```ruby
# The conversation entry job automatically broadcasts updates
class Raif::ConversationEntryJob < ApplicationJob
  def perform(conversation_entry:)
    conversation_entry.process_entry!
    conversation_entry.broadcast_replace_to conversation_entry.raif_conversation
  end
end
```

```erb
<!-- In your view -->
<%= turbo_stream_from @conversation %>

<div id="<%= dom_id(@conversation, :entries) %>">
  <%= render @conversation.entries.oldest_first %>
</div>
```

---

## Advanced Configuration

### Custom Conversation Types

```ruby
class Raif::Conversations::TechnicalSupport < Raif::ApplicationConversation
  before_create -> { 
    self.available_model_tools = [
      "Raif::ModelTools::DatabaseQuery",
      "Raif::ModelTools::LogAnalysis"
    ]
  }
  
  def build_system_prompt
    <<~PROMPT
      You are a technical support specialist with expertise in:
      - API integration issues
      - Database troubleshooting
      - Performance optimization
      
      Always provide code examples when relevant.
    PROMPT
  end
  
  def process_model_response_message(message:, entry:)
    # Custom processing based on content
    if message.include?('escalate')
      create_support_ticket(entry)
    end
    
    message
  end
  
  private
  
  def create_support_ticket(entry)
    SupportTicket.create!(
      conversation: self,
      content: entry.model_response_message,
      priority: :high
    )
  end
end
```

### Managing Context Length

```ruby
class Raif::Conversations::LongRunning < Raif::ApplicationConversation
  def llm_messages
    # Limit to recent entries to stay within token limits
    recent_entries = entries.oldest_first.last(20)
    build_messages_from_entries(recent_entries)
  end
end
```

---

## Testing

```ruby
RSpec.describe Raif::Conversations::CustomerSupport do
  let(:user) { create(:user) }
  let(:conversation) { described_class.create!(creator: user) }
  
  describe "#process_entry!" do
    it "processes user messages and generates responses" do
      stub_raif_conversation(conversation) do |messages, model_completion|
        "I'd be happy to help with your account issue."
      end
      
      entry = conversation.entries.create!(
        user_message: "I can't access my account",
        creator: user
      )
      
      entry.process_entry!
      
      expect(entry).to be_completed
      expect(entry.model_response_message).to include('help with your account')
    end
  end
  
  describe "#build_system_prompt" do
    it "includes customer support guidelines" do
      prompt = conversation.build_system_prompt
      expect(prompt).to include('customer support assistant')
    end
  end
end
``` 