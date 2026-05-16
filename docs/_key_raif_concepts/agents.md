---
layout: default
title: Agents
nav_order: 3
description: "ReAct-style agents that can use tools in loops"
---

{% include table-of-contents.md %}

# Agents Overview

Raif also provides `Raif::Agents::NativeToolCallingAgent`, which implements a ReAct-style agent loop using [tool calls](model_tools):

```ruby
# Create a new agent
agent = Raif::Agents::NativeToolCallingAgent.new(
  task: "Research the history of the Eiffel Tower",
  available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
  creator: current_user
)

# Run the agent and get the final answer
final_answer = agent.run!

# Or run the agent and monitor its progress
agent.run! do |conversation_history_entry|
  Turbo::StreamsChannel.broadcast_append_to(
    :my_agent_channel,
    target: "agent-progress",
    partial: "my_partial_displaying_agent_progress",
    locals: { agent: agent, conversation_history_entry: conversation_history_entry }
  )
end
```

On each step of the agent loop, an entry will be added to the `Raif::Agent#conversation_history` and, if you pass a block to the `run!` method, the block will be called with the `conversation_history_entry` as an argument. You can use this to monitor and display the agent's progress in real-time.

The conversation_history_entry will be a hash with "role" and "content" keys:
```ruby
{
  "role" => "assistant",
  "content" => "a message here"
}
```

`Raif::Agents::NativeToolCallingAgent` prefers provider-side tool enforcement when the selected model can faithfully enforce it for the current tool set. For provider/tool combinations that cannot do that, Raif falls back to runtime validation in the agent loop and logs a warning instead of changing your caller API.

## Requiring Tool Calls

You can force the model to call a tool on a given iteration by overriding `tool_choice_for_iteration` and/or `required_tool_for_iteration` on your agent subclass:

- Return a specific model tool class (e.g. `Raif::ModelTools::AgentFinalAnswer`) to require that exact tool.
- Return `:required` to require that the model call *some* tool (any one of the agent's `available_model_tools`).
- Return `nil` (the default) to leave tool use up to the model.

```ruby
class Raif::Agents::ResearchAgent < Raif::Agent
  def tool_choice_for_iteration
    # Force a final answer on the last iteration
    return Raif::ModelTools::AgentFinalAnswer if iteration_count >= max_iterations - 1

    # Otherwise require that the model calls some tool
    :required
  end
end
```

Under the hood this maps to each provider's native "required tool" API (OpenAI `"required"`, Anthropic `{ type: "any" }`, Bedrock `{ any: {} }`, Google `{ mode: "ANY" }`, OpenRouter via OpenAI). When a specific tool is required, Raif retries on misses and fails the run if the model still does not comply on the final allowed attempt.

The same `tool_choice:` kwarg is also supported directly on `Raif::Llm#chat`:

```ruby
llm.chat(
  messages: messages,
  available_model_tools: [Raif::ModelTools::WikipediaSearch],
  tool_choice: :required
)
```

# Creating Custom Agents

You can create custom agents using the generator:
```bash
rails generate raif:agent WikipediaResearchAgent
```

This will create a new agent in `app/models/raif/agents/wikipedia_research_agent.rb` along with a system prompt [template](../learn_more/prompt_templates) at `app/views/raif/agents/wikipedia_research_agent.system_prompt.erb`.

You can define the system prompt either in the template or by overriding `build_system_prompt` in the class:

```ruby
module Raif
  module Agents
    class WikipediaResearchAgent < Raif::Agent
      # If you want to always include a certain set of model tools with this agent type,
      # uncomment this callback to populate the available_model_tools attribute with your desired model tools.
      # before_create -> {
      #   self.available_model_tools ||= [
      #     Raif::ModelTools::WikipediaSearch,
      #     Raif::ModelTools::FetchUrl
      #   ]
      # }

      # Enter your agent's system prompt here. Alternatively, you can define it in
      # app/views/raif/agents/wikipedia_research_agent.system_prompt.erb
      def build_system_prompt
        # TODO: Implement your system prompt here
      end

      # Each iteration of the agent loop will generate a new Raif::ModelCompletion record and
      # then call this method with it as an argument.
      def process_iteration_model_completion(model_completion)
        # TODO: Implement your iteration processing here
      end
    end
  end
end

```

---

**Read next:** [Model Tools](model_tools)
