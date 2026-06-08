# frozen_string_literal: true

class Raif::ModelTools::CurrentTemperatureTestTool < Raif::ModelTool
  tool_arguments_schema do
    string :zip_code, description: "The zip code to get the current temperature for"
  end

  tool_description do
    "A tool to get the current temperature for a given zip code"
  end

  class << self
    def process_invocation(tool_invocation)
      tool_invocation.update!(
        result: {
          temperature: 72
        }
      )

      tool_invocation.result
    end

    def triggers_immediate_llm_follow_up?(_invocation)
      true
    end

    def format_result_for_llm(invocation)
      zip_code = invocation.tool_arguments["zip_code"]
      temperature = invocation.result["temperature"]

      "The current temperature for zip code #{zip_code} is #{temperature} degrees Fahrenheit."
    end
  end
end
