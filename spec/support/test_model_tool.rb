# frozen_string_literal: true

class Raif::TestModelTool < Raif::ModelTool
  def process_invocation(tool_arguments)
  end

  def self.tool_arguments_schema
    {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          description: { type: "string" },
        },
        required: ["title", "description"],
      },
    }
  end

  def clean_tool_arguments(tool_arguments)
    return unless tool_arguments.is_a?(Array)

    tool_arguments.map do |arg|
      {
        "title" => arg["title"],
        "description" => arg["description"]
      }
    end
  end
end
