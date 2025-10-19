# frozen_string_literal: true

module Raif
  module Agents
    class NativeToolCallingAgent < Raif::Agent
      validate :ensure_llm_supports_native_tool_use
      validates :available_model_tools, length: {
        minimum: 2,
        message: ->(_object, _data) {
          I18n.t("raif.agents.native_tool_calling_agent.errors.available_model_tools.too_short")
        }
      }

      before_validation -> {
        # If there is no final answer tool added, add it
        unless available_model_tools_map.key?("agent_final_answer")
          available_model_tools << "Raif::ModelTools::AgentFinalAnswer"
        end
      }

      def build_system_prompt
        <<~PROMPT.strip
          You are an AI agent that follows the ReAct (Reasoning + Acting) framework to complete tasks step by step using tool/function calls.

          At each step, you must:
          1. Think about what to do next.
          2. Choose and invoke exactly one tool/function call based on that thought.
          3. Observe the results of the tool/function call.
          4. Use the results to update your thought process.
          5. Repeat steps 1-4 until the task is complete.
          6. Provide a final answer to the user's request.

          For your final answer:
          - Use the agent_final_answer tool/function with your complete answer as the "final_answer" parameter.
          - Your answer should be comprehensive and directly address the user's request.

          Guidelines
          - Always think step by step
          - Be concise in your reasoning but thorough in your analysis
          - If a tool returns an error, try to understand why and adjust your approach
          - If you're unsure about something, explain your uncertainty, but do not make things up
          - Always provide a final answer that directly addresses the user's request

          Remember: Your goal is to be helpful, accurate, and efficient in solving the user's request.#{system_prompt_language_preference}
        PROMPT
      end

    private

      def native_model_tools
        available_model_tools
      end

      def process_iteration_model_completion(model_completion)
        if model_completion.parsed_response.present?
          add_conversation_history_entry({
            role: "assistant",
            content: model_completion.parsed_response
          })
        end

        if model_completion.response_tool_calls.blank?
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: No tool call found. I need to make a tool call at each step. Available tools: #{available_model_tools_map.keys.join(", ")}</observation>" # rubocop:disable Layout/LineLength
          })
          return
        end

        tool_call = model_completion.response_tool_calls.first

        unless tool_call["name"] && tool_call["arguments"]
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: Invalid action specified. Please provide a valid action, formatted as a JSON object with 'tool' and 'arguments' keys.</observation>" # rubocop:disable Layout/LineLength
          })
          return
        end

        tool_name = tool_call["name"]
        tool_arguments = tool_call["arguments"]

        # Add assistant's response to conversation history (without the actual tool calls)
        # add_conversation_history_entry({
        #   role: "assistant",
        #   content: "<thought>I need to use the #{tool_name} tool to help with this task.</thought>"
        # })

        # Check if we have a final answer. If yes, we're done.
        if tool_name == "agent_final_answer"
          self.final_answer = tool_arguments["final_answer"]
          add_conversation_history_entry({ role: "assistant", content: "<answer>#{final_answer}</answer>" })
          return
        end

        # Add the tool call to conversation history
        add_conversation_history_entry({
          role: "assistant",
          content: "<action>\n#{JSON.pretty_generate(tool_call)}\n</action>"
        })

        # Find the tool class and process it
        tool_klass = available_model_tools_map[tool_name]

        # The model tried to use a tool that doesn't exist
        unless tool_klass
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: Tool '#{tool_name}' not found. Available tools: #{available_model_tools_map.keys.join(", ")}</observation>"
          })
          return
        end

        unless JSON::Validator.validate(tool_klass.tool_arguments_schema, tool_arguments)
          add_conversation_history_entry({
            role: "assistant",
            content: "<observation>Error: Invalid tool arguments. Please provide valid arguments for the tool '#{tool_name}'. Tool arguments schema: #{tool_klass.tool_arguments_schema.to_json}</observation>" # rubocop:disable Layout/LineLength
          })
          return
        end

        # Process the tool and add observation to history
        tool_invocation = tool_klass.invoke_tool(tool_arguments: tool_arguments, source: self)
        observation = tool_klass.observation_for_invocation(tool_invocation)

        add_conversation_history_entry({
          role: "assistant",
          content: "<observation>\n#{observation}\n</observation>"
        })
      end

      def ensure_llm_supports_native_tool_use
        unless llm.supports_native_tool_use?
          errors.add(:base, "Raif::Agent#llm_model_key must use an LLM that supports native tool use")
        end
      end

    end
  end
end
