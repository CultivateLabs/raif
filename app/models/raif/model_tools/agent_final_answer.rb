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
    def format_result_for_llm(invocation)
      return "No answer provided" unless invocation.result.present?

      invocation.result
    end

    # No override on triggers_immediate_follow_up_turn? - it stays at the
    # default (false). AgentFinalAnswer is consumed exclusively by Raif
    # agents, whose own loop terminates as soon as this tool is called.
    # The hook only governs conversation-level follow-ups; in the unlikely
    # event AgentFinalAnswer ever ran inside a conversation, prompting the
    # model again right after it explicitly said "this is my final answer"
    # would be exactly the wrong thing to do.

    def process_invocation(tool_invocation)
      tool_invocation.update!(result: tool_invocation.tool_arguments["final_answer"])
      tool_invocation.result
    end
  end

end
