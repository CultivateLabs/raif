# frozen_string_literal: true

module Raif::Concerns::Llms::Bedrock::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    tools = []

    # If we're looking for a JSON response, add a tool to the request that the model can use to provide a JSON response
    if model_completion.response_format_json? && model_completion.json_response_schema.present?
      tools << {
        name: "json_response",
        description: "Generate a structured JSON response based on the provided schema.",
        input_schema: { json: model_completion.json_response_schema }
      }
    end

    model_completion.available_model_tools_map.each do |_tool_name, tool|
      tools << if tool.provider_managed?
        raise Raif::Errors::UnsupportedFeatureError,
          "Invalid provider-managed tool: #{tool.name} for #{key}"
      else
        {
          name: tool.tool_name,
          description: tool.tool_description,
          input_schema: { json: tool.tool_arguments_schema }
        }
      end
    end

    return {} if tools.blank?

    {
      tools: tools.map{|tool| { tool_spec: tool } }
    }
  end
end
