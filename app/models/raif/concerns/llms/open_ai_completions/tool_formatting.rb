# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    model_completion.available_model_tools_map.map do |_tool_name, tool|
      if tool.provider_managed?
        raise Raif::Errors::UnsupportedFeatureError,
          "Raif doesn't yet support provider-managed tools for the OpenAI Completions API. Consider using the OpenAI Responses API instead."
      else
        # It's a developer-managed tool
        validate_json_schema!(tool.tool_arguments_schema)

        {
          type: "function",
          function: {
            name: tool.tool_name,
            description: tool.tool_description,
            parameters: tool.tool_arguments_schema
          }
        }
      end
    end
  end
end
