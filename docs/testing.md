---
layout: default
title: Testing
nav_order: 11
description: "Testing Raif components in your Rails application"
---

# Testing
{: .no_toc }

Test AI-powered features with RSpec helpers and stubbing utilities without making actual API calls.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Setup

### RSpec Configuration

```ruby
# spec/rails_helper.rb
require "raif/rspec"

RSpec.configure do |config|
  config.include Raif::RspecHelpers
  config.include FactoryBot::Syntax::Methods
end
```

### Test Environment

```ruby
# config/environments/test.rb
Rails.application.configure do
  config.after_initialize do
    Raif.configure do |raif_config|
      raif_config.default_llm_model_key = 'raif_test_llm_model'
    end
  end
end
```

---

## Testing Tasks

### Basic Testing

```ruby
RSpec.describe Raif::Tasks::DocumentSummarization do
  let(:user) { create(:user) }
  let(:document) { create(:document, content: "This is a long document about AI...") }
  
  it "generates a summary" do
    stub_raif_task(described_class) do |messages, model_completion|
      "This document discusses artificial intelligence and its applications."
    end
    
    task = described_class.run(
      document: document,
      creator: user
    )
    
    expect(task).to be_completed
    expect(task.parsed_response).to include("artificial intelligence")
  end
  
  it "includes document content in prompt" do
    stub_raif_task(described_class) do |messages, model_completion|
      prompt_content = messages.first["content"]
      expect(prompt_content).to include(document.content)
      "Summary"
    end
    
    described_class.run(document: document, creator: user)
  end
end
```

### JSON Response Testing

```ruby
RSpec.describe Raif::Tasks::DataAnalysis do
  let(:user) { create(:user) }
  
  it "returns structured analysis data" do
    stub_raif_task(described_class) do |messages, model_completion|
      {
        "summary" => "Dataset contains 2 records",
        "average_age" => 27.5,
        "insights" => ["Young demographic"]
      }.to_json
    end
    
    task = described_class.run(dataset: dataset, creator: user)
    
    expect(task).to be_completed
    parsed_result = task.parsed_response
    expect(parsed_result["summary"]).to eq("Dataset contains 2 records")
    expect(parsed_result["average_age"]).to eq(27.5)
  end
end
```

---

## Testing Conversations

```ruby
RSpec.describe Raif::Conversation do
  let(:user) { create(:user) }
  let(:conversation) { create(:raif_conversation, creator: user) }
  
  it "processes user entry and generates AI response" do
    entry = create(:raif_conversation_entry,
      raif_conversation: conversation,
      creator: user,
      user_message: "What is the capital of France?"
    )
    
    stub_raif_conversation(conversation) do |messages, model_completion|
      "The capital of France is Paris."
    end
    
    entry.process_entry!
    
    expect(entry).to be_completed
    expect(entry.model_response_message).to eq("The capital of France is Paris.")
  end
  
  it "maintains conversation context" do
    # First entry
    entry1 = conversation.entries.create!(
      user_message: "Hello, I need help",
      creator: user
    )
    
    stub_raif_conversation(conversation) do |messages, model_completion|
      "Hello! How can I help you?"
    end
    entry1.process_entry!
    
    # Second entry - should include context
    entry2 = conversation.entries.create!(
      user_message: "I can't log in",
      creator: user
    )
    
    stub_raif_conversation(conversation) do |messages, model_completion|
      expect(messages.length).to be >= 2
      expect(messages.first["content"]).to include("Hello, I need help")
      "I'll help you troubleshoot this."
    end
    
    entry2.process_entry!
  end
end
```

### Custom Conversation Types

```ruby
RSpec.describe Raif::Conversations::CustomerSupport do
  let(:user) { create(:user) }
  let(:conversation) { described_class.create!(creator: user) }
  
  it "includes customer support instructions" do
    prompt = conversation.build_system_prompt
    expect(prompt).to include("customer support")
  end
  
  it "filters inappropriate content" do
    entry = conversation.entries.build(creator: user)
    
    result = conversation.process_model_response_message(
      message: "This contains inappropriate_word content",
      entry: entry
    )
    
    expect(result).to eq("This contains [FILTERED] content")
  end
end
```

---

## Testing Agents

```ruby
RSpec.describe Raif::Agents::ResearchAssistant do
  let(:user) { create(:user) }
  let(:agent) do
    described_class.new(
      task: "What is the capital of France?",
      creator: user
    )
  end
  
  before { agent.save! }
  
  it "completes the research task" do
    stub_raif_agent(agent) do |messages, model_completion|
      case agent.iteration_count
      when 1
        '<thought>I need to search for information.</thought>
         <action>{"tool": "wikipedia_search", "arguments": {"query": "capital of France"}}</action>'
      when 2
        '<thought>Based on the search results, I have the answer.</thought>
         <answer>The capital of France is Paris.</answer>'
      end
    end
    
    final_answer = agent.run!
    
    expect(agent).to be_completed
    expect(final_answer).to include("Paris")
    expect(agent.iteration_count).to eq(2)
  end
  
  it "includes research methodology in system prompt" do
    prompt = agent.build_system_prompt
    expect(prompt).to include("research assistant")
    expect(prompt).to include("step-by-step")
  end
end
```

---

## Factories

### Built-in Factories

```ruby
# Basic usage
conversation = create(:raif_conversation, creator: user)
conversation_with_entries = create(:raif_conversation, :with_entries, creator: user)

entry = create(:raif_conversation_entry, 
               raif_conversation: conversation,
               creator: user,
               user_message: "Hello")

agent = create(:raif_agent, creator: user, task: "Test task")
completed_agent = create(:raif_agent, :completed, creator: user)
```

### Custom Factories

```ruby
# spec/factories/custom_raif_factories.rb
FactoryBot.define do
  factory :customer_support_conversation, 
          class: 'Raif::Conversations::CustomerSupport',
          parent: :raif_conversation
  
  factory :research_agent,
          class: 'Raif::Agents::ResearchAssistant',
          parent: :raif_agent do
    task { "Research renewable energy trends" }
  end
end
```

---

## Error Handling

```ruby
RSpec.describe "Error Scenarios" do
  let(:user) { create(:user) }
  
  it "handles API failures gracefully" do
    task = Raif::Tasks::DocumentSummarization.new(
      document: create(:document),
      creator: user
    )
    
    allow(task).to receive(:llm).and_raise(Faraday::ConnectionFailed.new("Connection failed"))
    
    expect { task.run }.not_to raise_error
    expect(task).to be_failed
  end
  
  it "handles malformed JSON responses" do
    stub_raif_task(Raif::Tasks::JsonTask) do |messages, model_completion|
      "This is not valid JSON"
    end
    
    task = Raif::Tasks::JsonTask.run(creator: user)
    
    expect(task).to be_completed
    expect(task.raw_response).to eq("This is not valid JSON")
  end
end
```

---

## Best Practices

### Test Organization
```ruby
RSpec.describe Raif::Tasks::DocumentSummarization do
  describe "prompt building" do
    # Test prompt generation logic
  end
  
  describe "response processing" do  
    # Test response parsing and handling
  end
  
  describe "error handling" do
    # Test failure scenarios
  end
end
```

### Efficient Test Data
```ruby
# Use let blocks for lazy loading
let(:user) { create(:user) }
let(:document) { create(:document, :with_content) }

# Use build instead of create when possible
let(:task) { build(:raif_task, creator: user) }
``` 