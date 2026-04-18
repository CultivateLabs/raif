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

### Dynamic Schemas

If your tool's schema needs to vary based on runtime context (e.g. values that can change between process restarts), pass `dynamic: true`. The block is re-evaluated on each call to `tool_arguments_schema`:

```ruby
class Raif::ModelTools::DocumentSearch < Raif::ModelTool
  tool_arguments_schema dynamic: true do
    string :query, description: "The query to search for"
    string :collection, description: "The collection to search", enum: Collection.pluck(:slug)
  end
end
```

### Source-Aware Schemas

When your tool's schema depends on *who's calling it* (typically the agent or conversation invoking it), declare the schema block with a single parameter. The block receives the calling `source` — usually the agent — on every evaluation, so you can gate fields on per-run state without reading thread-local or global variables.

```ruby
class Raif::ModelTools::FinalAnswer < Raif::ModelTool
  tool_arguments_schema do |source|
    string :summary

    # Only expose `relevant_documents` when the calling agent has a
    # document-returning tool in its toolset. This prevents the model
    # from hallucinating document IDs when no search tool was available.
    if source.respond_to?(:document_search_available?) && source.document_search_available?
      array :relevant_documents do
        object do
          integer :document_id
          string :relevance, enum: ["high", "medium", "low"]
          string :rationale
        end
      end
    end
  end
end
```

`dynamic: true` is implied for arity-1 tool schema blocks, since a source-dependent schema must re-evaluate on every read.

Source is threaded through every call path that renders or validates the schema: all LLM tool formatters, the shared tool-call validator used by agents and conversation entries, and `ModelToolInvocation`'s schema lookup — so the schema the model sees matches the schema the caller validates against.

The same arity-1 form is supported on `example_model_invocation`:

```ruby
example_model_invocation do |source|
  args = { "summary" => "…" }

  if source.respond_to?(:document_search_available?) && source.document_search_available?
    args["relevant_documents"] = [{ "document_id" => 1234, "relevance" => "high" }]
  end

  { "name" => tool_name, "arguments" => args }
end
```

Source-aware blocks should tolerate a `nil` source — the schema is still rendered in admin views and in class-level introspection where no caller exists. Treat nil as "least-privilege" and don't expose optional fields.

**Back-compat for legacy overrides.** Tools whose class-method overrides predate the `source:` keyword (e.g. `def self.tool_arguments_schema; {...}; end`, `def self.prepare_tool_arguments(arguments); ...; end`) continue to work unchanged. Raif's internals route through compat helpers (`tool_arguments_schema_for_source`, `prepare_tool_arguments_for_source`, `example_model_invocation_for_source`) that inspect the tool's method signature and pass `source:` only when the override accepts it.

## Preparing Tool Arguments

Before a tool's arguments are validated against its schema, Raif calls `prepare_tool_arguments` on the tool class. The default implementation strips any keys the LLM returned that are not declared in `tool_arguments_schema` and logs a warning. This handles LLMs that occasionally hallucinate extra parameters and would otherwise fail strict schema validation.

You can override `prepare_tool_arguments` in your tool to add type coercion or default injection. To opt into the caller `source`, accept it as a keyword argument:

```ruby
class Raif::ModelTools::DocumentSearch < Raif::ModelTool
  def self.prepare_tool_arguments(arguments, source: nil)
    prepared = super # strips undeclared keys, using the source-aware schema
    prepared["max_results"] ||= 10
    prepared
  end
end
```

Overrides that use the legacy signature `def self.prepare_tool_arguments(arguments)` continue to work — Raif's compat helper calls them without the `source:` kwarg.

## Processing Model Tool Invocations

When the LLM invokes your tool, Raif will call your tool's `process_invocation` method with a `Raif::ModelToolInvocation` record as an argument.

You should implement `process_invocation` to perform whatever actions are appropriate for your tool and store the results in the `tool_invocation.result` JSON column.

## Model Tool Observations

When your tool is being invoked in a [conversation](conversations) or [agent](agents), the results of the tool invocation are provided back to the LLM as an observation.

When `triggers_observation_to_model?` returns `true`, Raif will call `observation_for_invocation` to build the model-facing observation. This observation can differ from the raw `tool_invocation.result`, which remains persisted for rendering and inspection.

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
| Google AI              | ✅        | ✅            | ❌               |

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

Note for Google AI: Gemini's provider-side `"require any tool"` enforcement only applies to declared function tools. If you use `tool_choice: :required` with Google provider-managed tools, or mix provider-managed and developer-managed tools, Raif logs a warning and falls back to runtime validation instead of provider-enforced required-tool selection.

---

**Read next:** [Web Admin](../learn_more/web_admin)
