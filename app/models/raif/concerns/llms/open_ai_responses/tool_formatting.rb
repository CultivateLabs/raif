# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiResponses::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    model_completion.available_model_tools_map.map do |_tool_name, tool|
      if tool.provider_managed?
        format_provider_managed_tool(tool)
      else
        # It's a developer-managed tool
        validate_json_schema!(tool.tool_arguments_schema)

        {
          type: "function",
          name: tool.tool_name,
          description: tool.tool_description,
          parameters: tool.tool_arguments_schema
        }
      end
    end
  end

  def format_provider_managed_tool(tool)
    validate_provider_managed_tool_support!(tool)

    case tool.name
    when "Raif::ModelTools::ProviderManaged::WebSearch"
      { type: "web_search_preview" }
    when "Raif::ModelTools::ProviderManaged::CodeExecution"
      {
        type: "code_interpreter",
        container: { "type": "auto" }
      }
    when "Raif::ModelTools::ProviderManaged::ImageGeneration"
      { type: "image_generation" }
    else
      raise Raif::Errors::UnsupportedFeatureError,
        "Invalid provider-managed tool: #{tool.name} for #{key}"
    end
  end
end
