# frozen_string_literal: true

class Raif::ModelTools::AgentFinalAnswer < Raif::ModelTool
  tool_arguments_schema do
    string "final_answer", description: "Your complete and final answer to the user's question or task"
  end

  example_model_invocation do
    {
      "name" => tool_name,
      "arguments" => { "final_answer": "The answer to the user's question or task" }
    }
  end

  tool_description do
    "Provide your final answer to the user's question or task"
  end

  class << self
    def observation_for_invocation(tool_invocation)
      return "No answer provided" unless tool_invocation.result.present?

      tool_invocation.result
    end

    def process_invocation(tool_invocation)
      tool_invocation.update!(result: tool_invocation.tool_arguments["final_answer"])
      tool_invocation.result
    end
  end

end
