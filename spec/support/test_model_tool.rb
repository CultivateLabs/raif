# frozen_string_literal: true

class Raif::TestModelTool < Raif::ModelTool
  def self.process_invocation(tool_arguments)
  end

  def self.tool_description
    "Mock Tool Description"
  end

  def self.example_model_invocation
    {
      "name": tool_name,
      "arguments": { "items": [{ "title": "foo", "description": "bar" }] }
    }
  end

  def self.tool_arguments_schema
    {
      type: "object",
      additionalProperties: false,
      required: ["items"],
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              title: { type: "string" },
              description: { type: "string" },
            },
            required: ["title", "description"],
          }
        }
      }
    }
  end

  def self.observation_for_invocation(tool_invocation)
    "Mock Observation"
  end

  def self.clean_tool_arguments(tool_arguments)
    return unless tool_arguments.is_a?(Array)

    tool_arguments.map do |arg|
      {
        "title" => arg["title"],
        "description" => arg["description"]
      }
    end
  end
end
