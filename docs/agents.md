---
layout: default
title: Agents
nav_order: 5
description: "ReAct-style agents that can use tools in loops"
---

# Agents
{: .no_toc }

Autonomous AI systems that can reason, plan, and execute actions using available tools through iterative problem solving.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Raif Agents implement the ReAct pattern, allowing LLMs to:
1. **Reason** about problems and plan their approach
2. **Act** by invoking available tools
3. **Observe** the results of their actions
4. **Iterate** until they reach a satisfactory solution

### Key Features
- **Tool Integration**: Access to custom model tools and provider-managed tools
- **Iterative Problem Solving**: Multi-step reasoning and action cycles
- **Flexible Architecture**: Easy to extend with new tools and capabilities
- **Error Recovery**: Robust handling of tool failures and unexpected situations

---

## Creating an Agent

```bash
rails generate raif:agent ResearchAssistant
```

```ruby
class Raif::Agents::ResearchAssistant < Raif::ApplicationAgent
  before_create -> {
    self.available_model_tools = [
      "Raif::ModelTools::ProviderManaged::WebSearch",
      "Raif::ModelTools::WikipediaSearch",
      "Raif::ModelTools::FetchUrl"
    ]
  }
  
  def build_system_prompt
    <<~PROMPT
      You are a research assistant that helps users find, analyze, and synthesize information.
      
      Available tools:
      - WebSearch: Search the internet for current information
      - WikipediaSearch: Search Wikipedia for factual information
      - FetchUrl: Retrieve content from specific web pages
      
      Approach each task systematically:
      1. Break down the user's request into actionable steps
      2. Use appropriate tools to gather and analyze information
      3. Synthesize findings into a clear, well-structured response
      
      Always think step-by-step and explain your reasoning.
    PROMPT
  end
end
```

---

## Usage

### Running an Agent

```ruby
# Create and run an agent
agent = Raif::Agents::ResearchAssistant.new(
  task: "Research the latest developments in renewable energy storage technologies",
  creator: current_user
)

agent.save!
final_answer = agent.run!

puts final_answer
```

### Monitoring Progress

```ruby
agent = Raif::Agents::ResearchAssistant.new(
  task: "Analyze quarterly sales data and identify trends",
  creator: current_user
)
agent.save!

agent.run! do |conversation_history_entry|
  puts "New entry: #{conversation_history_entry}"
  
  # Broadcast real-time updates
  ActionCable.server.broadcast(
    "agent_#{agent.id}",
    { 
      type: 'iteration_update',
      entry: conversation_history_entry,
      iteration: agent.iteration_count
    }
  )
end

puts "Final result: #{agent.final_answer}"
```

### Accessing Agent History

```ruby
# Get conversation history
agent.conversation_history.each_with_index do |entry, index|
  puts "Entry #{index + 1}: #{entry['role']} - #{entry['content'][0..100]}..."
end

# Get tool invocations
tool_invocations = agent.raif_model_tool_invocations.includes(:raif_model_tool_invocation_result)
tool_invocations.each do |invocation|
  puts "Tool: #{invocation.tool_name}"
  puts "Arguments: #{invocation.tool_arguments}"
  puts "Result: #{invocation.result&.dig('success') ? 'Success' : 'Failed'}"
end

# Check status
puts "Status: #{agent.status}"  # :pending, :in_progress, :completed, :failed
puts "Iterations: #{agent.iteration_count}"
```

---

## Agent Types

### ReAct Agent
Classic ReAct implementation that processes thought/action/observation cycles:

```ruby
class Raif::Agents::MyReActAgent < Raif::Agents::ReActAgent
  before_create -> {
    self.available_model_tools = [
      "Raif::ModelTools::WikipediaSearch",
      "Raif::ModelTools::FetchUrl"
    ]
  }
end

agent = Raif::Agents::MyReActAgent.new(
  task: "What is the capital of France and what is its population?",
  creator: current_user
)
agent.save!
agent.run!
```

### Native Tool Calling Agent
Uses the LLM provider's native tool calling capabilities:

```ruby
class Raif::Agents::MyNativeAgent < Raif::Agents::NativeToolCallingAgent
  before_create -> {
    self.available_model_tools = [
      "Raif::ModelTools::ProviderManaged::WebSearch",
      "Raif::ModelTools::ProviderManaged::CodeExecution"
    ]
  }
end
```

---

## Advanced Configuration

### Custom Agent with Specialized Tools

```ruby
class Raif::Agents::DataAnalyst < Raif::ApplicationAgent
  before_create -> {
    self.available_model_tools = [
      "Raif::ModelTools::DatabaseQuery",
      "Raif::ModelTools::StatisticalAnalysis",
      "Raif::ModelTools::VisualizationGenerator"
    ]
  }
  
  def build_system_prompt
    <<~PROMPT
      You are a data analyst AI that helps users understand their data through:
      - Querying databases to extract relevant information
      - Performing statistical analysis to identify patterns
      - Creating visualizations to illustrate findings
      
      For each analysis request:
      1. First understand what data is needed
      2. Query the database to get the raw data
      3. Perform appropriate statistical analysis
      4. Create visualizations to support your findings
    PROMPT
  end
end
```

### Setting Agent Parameters

```ruby
agent = Raif::Agents::ResearchAssistant.new(
  task: "Research climate change impacts",
  creator: current_user,
  max_iterations: 15,  # Limit iterations to prevent infinite loops
  llm_model_key: "anthropic_claude_3_5_sonnet"  # Use specific model
)
```

---

## Error Handling

```ruby
class Raif::Agents::RobustAgent < Raif::ApplicationAgent
  def process_iteration_model_completion(model_completion)
    begin
      super
    rescue StandardError => e
      Rails.logger.error "Agent #{id} iteration #{iteration_count} failed: #{e.message}"
      
      # Add error context to conversation history
      add_conversation_history_entry({
        role: "assistant",
        content: "<observation>Error occurred: #{e.message}. Attempting to recover...</observation>"
      })
      
      recover_from_error(e)
    end
  end
  
  private
  
  def recover_from_error(error)
    case error
    when Faraday::TimeoutError
      add_conversation_history_entry({
        role: "assistant", 
        content: "<thought>The previous tool call timed out. I should try a different approach.</thought>"
      })
    else
      add_conversation_history_entry({
        role: "assistant",
        content: "<thought>An unexpected error occurred. I'll try to complete the task with available information.</thought>"
      })
    end
  end
end
```

---

## Testing

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
  
  describe "#run!" do
    it "completes the research task" do
      stub_raif_agent(agent) do |messages, model_completion|
        case agent.iteration_count
        when 1
          '<thought>I need to search for information about France\'s capital.</thought>
           <action>{"tool": "wikipedia_search", "arguments": {"query": "capital of France"}}</action>'
        when 2
          '<thought>Based on the search results, I now have the answer.</thought>
           <answer>The capital of France is Paris.</answer>'
        end
      end
      
      final_answer = agent.run!
      
      expect(agent).to be_completed
      expect(final_answer).to include("Paris")
      expect(agent.iteration_count).to eq(2)
    end
  end
  
  describe "#build_system_prompt" do
    it "includes tool descriptions" do
      prompt = agent.build_system_prompt
      
      expect(prompt).to include("research assistant")
      expect(prompt).to include("WebSearch")
      expect(prompt).to include("step-by-step")
    end
  end
end
```

---

## Background Processing

```ruby
class ProcessAgentJob < ApplicationJob
  def perform(agent_id)
    agent = Raif::Agent.find(agent_id)
    
    begin
      final_answer = agent.run!
      AgentNotificationService.notify_completion(agent, final_answer)
    rescue StandardError => e
      agent.update!(
        failed_at: Time.current,
        failure_reason: e.message
      )
      AgentNotificationService.notify_failure(agent, e)
    end
  end
end

# Usage
agent = Raif::Agents::ResearchAssistant.create!(
  task: "Long running research task",
  creator: current_user
)

ProcessAgentJob.perform_later(agent.id)
``` 