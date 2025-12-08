---
layout: default
title: JSON Schemas
nav_order: 5
description: "Defining JSON Schemas in Raif"
---

{% include table-of-contents.md %}

# JSON Schemas

Raif includes a DSL for defining [JSON schemas](https://json-schema.org/){:target="_blank"}. You can use this to define the attributes that should be included in JSON objects produced by the LLM. 

The DSL is utilized to define:
- JSON responses in [tasks](../key_raif_concepts/tasks#json-response-format-tasks) via the `json_response_schema` method
- Tool arguments of [model tool invocations](../key_raif_concepts/model_tools#tool-arguments-schema) via the `tool_arguments_schema` method

# Defining a JSON Schema

When defining a JSON schema, you can use the following methods:

- `string(name, options = {})`: Defines a string property
- `integer(name, options = {})`: Defines an integer property
- `number(name, options = {})`: Defines a number property
- `boolean(name, options = {})`: Defines a boolean property
- `object(name = nil, options = {}, &block)`: Defines an object property
- `array(name, options = {}, &block)`: Defines an array property
- `items(options = {})`: Defines the items of an array property

# Examples

## Task JSON Schema

```ruby
class MyPersonGenerationTask < Raif::Task
  json_response_schema do
    string :name, description: "The name of the person"
    integer :age, description: "The age of the person"
    boolean :is_student, description: "Whether the person is a student"

    # An array of pet objects
    array :pets do
      object do
        string :name, description: "The name of the pet"
        string :species, enum: ["dog", "cat", "bird", "fish"], description: "The species of the pet"
      end
    end

    # An array of strings
    array :favorite_colors do
      items type: "string"
    end
  end
end
```

This schema would expect the LLM to return a JSON object like:

```json
{
  "name": "John Doe",
  "age": 30,
  "is_student": false,
  "pets": [
    {
      "name": "Fido",
      "species": "dog"
    },
    {
      "name": "Whiskers",
      "species": "cat"
    }
  ],
  "favorite_colors": ["red", "blue", "green"]
}
```

## Tool Arguments Schema

```ruby
class WebSearchTool < Raif::ModelTool
  tool_arguments_schema do
    string :query, description: "The query to search the web for"
    integer :max_results, description: "The maximum number of results to return"
    boolean :include_images, description: "Whether to include images in the results"
    array :exclude_domains do
      items type: "string"
    end
  end
end
```

This schema would expect the LLM to return a JSON object like:

```json
{
  "query": "What is the capital of France?",
  "max_results": 5,
  "include_images": false,
  "exclude_domains": ["example.com", "example.org"]
}
```

# Instance-Dependent Schemas

Raif supports defining schemas that vary based on the instance state of a task or model tool. This is useful when you want different schema structures based on configuration, parameters, or other instance attributes.

## Defining an Instance-Dependent Schema

To create an instance-dependent schema, define your schema block with a parameter that represents the instance:

```ruby
class AnalysisTask < Raif::Task
  attr_accessor :include_details

  json_response_schema do |task|
    string :summary, description: "A summary of the analysis"

    # Conditionally include fields based on instance state
    if task.include_details
      object :details, description: "Detailed analysis" do
        string :methodology, description: "The methodology used"
        array :findings do
          items type: "string"
        end
      end
    end
  end

  def build_prompt
    "Analyze the following content..."
  end
end
```

---

**Read next:** [Embedding Models](embedding_models)