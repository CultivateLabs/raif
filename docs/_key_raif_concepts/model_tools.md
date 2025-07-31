---
layout: default
title: Model Tools
nav_order: 4
description: "Custom tools that agents and conversations can invoke"
---

{% include table-of-contents.md %}

# Model Tools

Raif supports the creation of custom tools that the LLM can invoke in your [agents](agents) and [conversations](conversations#tool-calling).

Two example tools are provided:
- [`Raif::ModelTools::WikipediaSearch`](https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/wikipedia_search.rb)
- [`Raif::ModelTools::FetchUrl`](https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/fetch_url.rb)

To create a new model tool, run the generator:
```bash
rails generate raif:model_tool GoogleSearch
```

This will create a new model tool in `app/models/raif/model_tools/google_search.rb`:

```ruby
class Raif::ModelTools::GoogleSearch < Raif::ModelTool
  # For example tool implementations, see: 
  # Wikipedia Search Tool: https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/wikipedia_search.rb
  # Fetch URL Tool: https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/fetch_url.rb

  # Define the schema for the arguments that the LLM should use when invoking your tool.
  # It should be a valid JSON schema. When the model invokes your tool,
  # the arguments it provides will be validated against this schema using JSON::Validator from the json-schema gem.
  #
  # All attributes will be required and additionalProperties will be set to false.
  #
  # This schema would expect the model to invoke your tool with an arguments JSON object like:
  # { "query" : "some query here" }
  tool_arguments_schema do
    string :query, description: "The query to search for"
  end

  # An example of how the LLM should invoke your tool. This should return a hash with name and arguments keys.
  # `to_json` will be called on it and provided to the LLM as an example of how to invoke your tool.
  example_model_invocation do
    {
      "name": tool_name,
      "arguments": { "query": "example query here" }
    }
  end

  tool_description do
    "Description of your tool that will be provided to the LLM so it knows when to invoke it"
  end

  # When your tool is invoked by the LLM in a Raif::Agent loop, 
  # the results of the tool invocation are provided back to the LLM as an observation.
  # This method should return whatever you want provided to the LLM.
  # For example, if you were implementing a GoogleSearch tool, this might return a JSON
  # object containing search results for the query.
  def self.observation_for_invocation(tool_invocation)
    return "No results found" unless tool_invocation.result.present?

    JSON.pretty_generate(tool_invocation.result)
  end

  # When the LLM invokes your tool, this method will be called with a `Raif::ModelToolInvocation` record as an argument.
  # It should handle the actual execution of the tool. 
  # For example, if you are implementing a GoogleSearch tool, this method should run the actual search
  # and store the results in the tool_invocation's result JSON column.
  def self.process_invocation(tool_invocation)
    # Extract arguments from tool_invocation.tool_arguments
    # query = tool_invocation.tool_arguments["query"]
    #
    # Process the invocation and perform the desired action
    # ...
    #
    # Store the results in the tool_invocation
    # tool_invocation.update!(
    #   result: {
    #     # Your result data structure
    #   }
    # )
    #
    # Return the result
    # tool_invocation.result
  end

end
```

## Tool Arguments Schema

When the LLM invokes your tool, it will include a JSON object of arguments. You can use the `tool_arguments_schema` method to define the schema for these arguments. When the model invokes your tool, the arguments it provides will be validated against this schema using JSON::Validator from the json-schema gem.

All attributes will be required and `additionalProperties` will be set to false.

# Provider-Managed Tools

In addition to the ability to create your own model tools, Raif supports provider-managed tools. These are tools that are built into certain LLM providers and run on the provider's infrastructure:

- **`Raif::ModelTools::ProviderManaged::WebSearch`**: Performs real-time web searches and returns relevant results
- **`Raif::ModelTools::ProviderManaged::CodeExecution`**: Executes code in a secure sandboxed environment (e.g. Python)
- **`Raif::ModelTools::ProviderManaged::ImageGeneration`**: Generates images based on text descriptions

Current provider-managed tool support:

| Provider               | Web Search | Code Execution | Image Generation |
|:-----------------------|:---------:|:-------------:|:---------------:|
| OpenAI Responses API   | ✅        | ✅            | ✅               |
| OpenAI Completions API | ❌        | ❌            | ❌               |
| Anthropic Claude       | ✅        | ✅            | ✅               |
| AWS Bedrock (Claude)   | ❌        | ❌            | ❌               |
| OpenRouter             | ❌        | ❌            | ❌               |

To use provider-managed tools, include them in the `available_model_tools` array:

```ruby
# In a conversation
conversation = Raif::Conversation.create!(
  creator: current_user,
  available_model_tools: [
    "Raif::ModelTools::ProviderManaged::WebSearch",
    "Raif::ModelTools::ProviderManaged::CodeExecution"
  ]
)

# In an agent
agent = Raif::Agents::ReActAgent.new(
  task: "Search for recent news about AI and create a summary chart",
  available_model_tools: [
    "Raif::ModelTools::ProviderManaged::WebSearch",
    "Raif::ModelTools::ProviderManaged::CodeExecution"
  ],
  creator: current_user
)

# Directly in a chat
llm = Raif.llm(:open_ai_responses_gpt_4_1)
model_completion = llm.chat(
  messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }], 
  available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
)
```