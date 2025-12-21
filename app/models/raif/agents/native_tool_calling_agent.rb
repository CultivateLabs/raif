# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_agents
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  completed_at           :datetime
#  conversation_history   :jsonb            not null
#  creator_type           :string           not null
#  failed_at              :datetime
#  failure_reason         :text
#  final_answer           :text
#  iteration_count        :integer          default(0), not null
#  llm_model_key          :string           not null
#  max_iterations         :integer          default(10), not null
#  requested_language_key :string
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  task                   :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  source_id              :bigint
#
# Indexes
#
#  index_raif_agents_on_created_at  (created_at)
#  index_raif_agents_on_creator     (creator_type,creator_id)
#  index_raif_agents_on_source      (source_type,source_id)
#
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
          - You **MUST** use the agent_final_answer tool/function to provide your final answer.
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

      def final_answer_tool
        available_model_tools_map["agent_final_answer"]
      end

      # Warn the agent that it must provide a final answer on the next iteration
      def before_iteration_llm_chat
        return unless final_iteration?

        warning_message = Raif::Messages::UserMessage.new(
          content: I18n.t("raif.agents.native_tool_calling_agent.final_answer_warning")
        )
        add_conversation_history_entry(warning_message.to_h)
      end

      # On the final iteration, force the agent to use the agent_final_answer tool
      def tool_choice_for_iteration
        return unless final_iteration?

        final_answer_tool
      end

      def process_iteration_model_completion(model_completion)
        assistant_response_message = model_completion.parsed_response if model_completion.parsed_response.present?

        # The model made no tool call in this completion. Tell it to make a tool call.
        if model_completion.response_tool_calls.blank?
          if assistant_response_message.present?
            assistant_message = Raif::Messages::AssistantMessage.new(content: assistant_response_message)
            add_conversation_history_entry(assistant_message.to_h)
          end

          error_message = Raif::Messages::UserMessage.new(
            content: "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: #{available_model_tools_map.keys.join(", ")}" # rubocop:disable Layout/LineLength
          )
          add_conversation_history_entry(error_message.to_h)

          return
        end

        tool_call = model_completion.response_tool_calls.first

        # Add the tool call to history
        tool_call_message = Raif::Messages::ToolCall.new(
          provider_tool_call_id: tool_call["provider_tool_call_id"],
          name: tool_call["name"],
          arguments: tool_call["arguments"],
          assistant_message: assistant_response_message,
          provider_metadata: tool_call["provider_metadata"]
        )
        add_conversation_history_entry(tool_call_message.to_h)

        tool_name = tool_call["name"]
        tool_arguments = tool_call["arguments"]
        tool_klass = available_model_tools_map[tool_name]

        # The model tried to use a tool that doesn't exist
        if tool_klass.blank?
          error_content = "Error: Tool '#{tool_name}' is not a valid tool. " \
            "Available tools: #{available_model_tools_map.keys.join(", ")}"
          error_message = Raif::Messages::UserMessage.new(content: error_content)
          add_conversation_history_entry(error_message.to_h)
          return
        end

        # Make sure the tool arguments match the tool's schema
        unless JSON::Validator.validate(tool_klass.tool_arguments_schema, tool_arguments)
          error_content = "Error: Invalid tool arguments for the tool '#{tool_name}'. " \
            "Tool arguments schema: #{tool_klass.tool_arguments_schema.to_json}"
          error_message = Raif::Messages::UserMessage.new(content: error_content)
          add_conversation_history_entry(error_message.to_h)
          return
        end

        # Process the tool invocation and add observation/result to history
        tool_invocation = tool_klass.invoke_tool(
          provider_tool_call_id: tool_call["provider_tool_call_id"],
          tool_arguments: tool_arguments,
          source: self
        )

        if tool_name == "agent_final_answer"
          self.final_answer = tool_invocation.result
        else
          add_conversation_history_entry(tool_invocation.as_tool_call_result_message)
        end
      end

      def ensure_llm_supports_native_tool_use
        unless llm.supports_native_tool_use?
          errors.add(:base, "Raif::Agent#llm_model_key must use an LLM that supports native tool use")
        end
      end

    end
  end
end
