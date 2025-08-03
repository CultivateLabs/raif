---
layout: default
title: Model Tools
nav_order: 4
description: "Custom tools that agents and conversations can invoke"
---

{% include table-of-contents.md %}

# Model Tools

Raif supports the creation of custom tools that the LLM can invoke in your [tasks](tasks), [conversations](conversations#tool-calling), and [agents](agents).

Two example tools are provided:
- `Raif::ModelTools::WikipediaSearch` - [View Source](https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/wikipedia_search.rb)
- `Raif::ModelTools::FetchUrl` - [View Source](https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/fetch_url.rb)

To create a new model tool, run the generator:
```bash
rails generate raif:model_tool GoogleSearch
```

This will create a new model tool in `app/models/raif/model_tools/google_search.rb` and a partial in `app/views/raif/model_tool_invocations/_google_search.html.erb` to display the tool invocation in the conversation interface.

Below is an example of a model tool that executes a Google search and returns the results:

```ruby
class Raif::ModelTools::GoogleSearch < Raif::ModelTool
  tool_description do
    "Searches Google for the given query and returns the results as JSON."
  end

  tool_arguments_schema do
    string :query, description: "The query to search the web for"
    integer :max_results, description: "The maximum number of results to return"
    boolean :include_images, description: "Whether to include images in the results"
    array :exclude_domains do
      items type: "string"
    end
  end

  class << self
    def observation_for_invocation(tool_invocation)
      return "No results found" unless tool_invocation.result.present?

      JSON.pretty_generate(tool_invocation.result)
    end

    # When your tool is invoked in a Raif::Conversation, should the result be automatically provided back to the model?
    # When true, observation_for_invocation will be used to produce the observation provided to the model
    def triggers_observation_to_model?
      false
    end

    def process_invocation(tool_invocation)
      # tool_invocation.tool_arguments will be a JSON object matching your tool_arguments_schema
      query = tool_invocation.tool_arguments["query"]
      max_results = tool_invocation.tool_arguments["max_results"]
      include_images = tool_invocation.tool_arguments["include_images"]
      exclude_domains = tool_invocation.tool_arguments["exclude_domains"]

      # Assumes your application has a GoogleSearchService that can execute a Google search
      # and return an array of results
      search_results = GoogleSearchService.execute(query: query, max_results: max_results, include_images: include_images, exclude_domains: exclude_domains)

      # Store the results in the tool_invocation
      tool_invocation.update!(result: search_results)
    end
  end

end
```

## Tool Arguments Schema

When the LLM invokes your tool, it will include a JSON object of arguments. You can use the `tool_arguments_schema` method to define the schema for these arguments. When the model invokes your tool, the arguments it provides will be validated against this schema using JSON::Validator from the json-schema gem.

See [JSON Schemas](../learn_more/json_schemas) for more information about defining JSON schemas.

## Processing Model Tool Invocations

When the LLM invokes your tool, Raif will call your tool's `process_invocation` method with a `Raif::ModelToolInvocation` record as an argument.

You should implement `process_invocation` to perform whatever actions are appropriate for your tool and store the results in the `tool_invocation.result` JSON column.

## Model Tool Observations

When your tool is being invoked in a [conversation](conversations) or [agent](agents), the results of the tool invocation are provided back to the LLM as an observation.

To control the manner in which the result is provided to the LLM, implement the `observation_for_invocation` method.

## Using Model Tools

`Raif::Task`, `Raif::Conversation`, and `Raif::Agent` all have an `available_model_tools` array to support the use of model tools. To make your tool available to the LLM, all you have to do is include it in the `available_model_tools` array.

Read more for each:
- [Tasks](../key_raif_concepts/tasks#using-model-tools)
- [Conversations](../key_raif_concepts/conversations#using-model-tools)
- [Agents](../key_raif_concepts/agents#using-model-tools)




# Provider-Managed Tools

In addition to the ability to create your own model tools, Raif supports provider-managed tools. These are tools that are built into certain LLM providers and run on the provider's infrastructure:

- **`Raif::ModelTools::ProviderManaged::WebSearch`** - Performs real-time web searches and considers relevant results when generating a response
- **`Raif::ModelTools::ProviderManaged::CodeExecution`** - Executes code in a secure sandboxed environment (e.g. Python)
- **`Raif::ModelTools::ProviderManaged::ImageGeneration`** - Generates images based on text descriptions

Current provider-managed tool support:

| Provider               | Web Search | Code Execution | Image Generation |
|:-----------------------|:---------:|:-------------:|:---------------:|
| OpenAI Responses API   | ✅        | ✅            | ✅               |
| OpenAI Completions API | ❌        | ❌            | ❌               |
| Anthropic Claude       | ✅        | ✅            | ❌               |
| AWS Bedrock (Claude)   | ❌        | ❌            | ❌               |
| OpenRouter             | ❌        | ❌            | ❌               |

To use provider-managed tools, include them in the `available_model_tools` array, just like any other model tool:

```ruby
# In a conversation
conversation = Raif::Conversation.create!(
  creator: current_user,
  available_model_tools: [
    "Raif::ModelTools::ProviderManaged::WebSearch",
    "Raif::ModelTools::ProviderManaged::CodeExecution"
  ]
)

# In a task definition
class MyTask < Raif::Task
  before_create ->{
    self.available_model_tools = [
      "Raif::ModelTools::ProviderManaged::WebSearch",
      "Raif::ModelTools::ProviderManaged::CodeExecution"
    ]
  }
end

# Or directly in a chat
llm = Raif.llm(:open_ai_responses_gpt_4_1)
model_completion = llm.chat(
  messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }], 
  available_model_tools: ["Raif::ModelTools::ProviderManaged::WebSearch"]
)
```

---

**Read next:** [Web Admin](../learn_more/web_admin)