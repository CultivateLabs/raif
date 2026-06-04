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
      include Raif::Concerns::ToolCallValidation

      RAW_ARGUMENTS_EXCERPT_LENGTH = 500

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

      def required_tool_for_iteration
        return final_answer_tool if final_iteration?

        nil
      end

      def before_iteration_llm_chat
        required_tool = current_iteration_required_tool
        return if required_tool.blank?

        warning_message = Raif::Messages::UserMessage.new(
          content: required_tool_warning_message(required_tool)
        )
        add_conversation_history_entry(warning_message.to_h)
      end

      def tool_choice_for_iteration
        return current_iteration_required_tool if current_iteration_required_tool.present?
        return :required if llm.supports_faithful_required_tool_choice?(native_model_tools)

        log_required_tool_choice_fallback_once!
        nil
      end

      def process_iteration_model_completion(model_completion)
        required_tool = current_iteration_required_tool
        assistant_response_message = model_completion.parsed_response if model_completion.parsed_response.present?

        # The response was cut off at the provider's max output token limit, so anything in
        # it (most importantly tool calls, whose arguments may be truncated mid-JSON) cannot
        # be trusted or persisted. Tell the model what happened and let it retry.
        if model_completion.truncated?
          if assistant_response_message.present?
            assistant_message = Raif::Messages::AssistantMessage.new(content: assistant_response_message)
            add_conversation_history_entry(assistant_message.to_h)
          end

          error_content = "Error: Your previous response exceeded the maximum output length and was cut off before completing. " \
            "Keep your responses and tool call arguments concise. Avoid very long queries or long, repetitive lists in arguments. " \
            "Prefer multiple smaller tool calls."
          handle_iteration_error(error_content, required_tool:)

          return
        end

        # The model made no tool call in this completion. Tell it to make a tool call.
        if model_completion.response_tool_calls.blank?
          if assistant_response_message.present?
            assistant_message = Raif::Messages::AssistantMessage.new(content: assistant_response_message)
            add_conversation_history_entry(assistant_message.to_h)
          end

          error_content = if required_tool.present?
            "Error: This iteration required the tool '#{required_tool.tool_name}', but the model response contained no tool call. Available tools: #{available_model_tools_map.keys.join(", ")}" # rubocop:disable Layout/LineLength
          else
            "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: #{available_model_tools_map.keys.join(", ")}" # rubocop:disable Layout/LineLength
          end
          handle_iteration_error(error_content, required_tool:)

          return
        end

        # The model returned multiple tool calls. We only allow one per step.
        if model_completion.response_tool_calls.length > 1
          if assistant_response_message.present?
            assistant_message = Raif::Messages::AssistantMessage.new(content: assistant_response_message)
            add_conversation_history_entry(assistant_message.to_h)
          end

          error_content = "Error: Multiple tool calls received. Only one tool call is allowed per step. " \
            "Please call exactly one tool at a time."
          handle_iteration_error(error_content, required_tool:)

          return
        end

        tool_call = model_completion.response_tool_calls.first
        validation = validate_tool_call(tool_call, available_model_tools_map, source: self)
        rejection_error = tool_call_rejection_error(validation, required_tool)

        # A rejected tool call is never added to conversation history. If it were, it would be
        # replayed to the provider on every subsequent request, which providers reject (e.g.
        # OpenAI 400s on a function_call input item with no paired function_call_output),
        # permanently failing the run. Instead, keep any assistant text and give the model
        # corrective feedback via a user message so it can retry.
        if rejection_error.present?
          if assistant_response_message.present?
            assistant_message = Raif::Messages::AssistantMessage.new(content: assistant_response_message)
            add_conversation_history_entry(assistant_message.to_h)
          end

          handle_iteration_error(rejection_error, required_tool:)
          return
        end

        # Validation passed, so prepared_arguments is a schema-valid Hash (extra keys stripped).
        tool_call_message = Raif::Messages::ToolCall.new(
          provider_tool_call_id: tool_call["provider_tool_call_id"],
          name: tool_call["name"],
          arguments: validation.prepared_arguments,
          assistant_message: assistant_response_message,
          provider_metadata: tool_call["provider_metadata"]
        )
        add_conversation_history_entry(tool_call_message.to_h)

        # Process the tool invocation and add observation/result to history
        tool_invocation = validation.tool_klass.invoke_tool(
          provider_tool_call_id: tool_call["provider_tool_call_id"],
          tool_arguments: validation.prepared_arguments,
          source: self
        )

        if validation.tool_name == "agent_final_answer"
          self.final_answer = tool_invocation.result
        else
          add_conversation_history_entry(tool_invocation.as_tool_call_result_message)
        end
      end

      # Returns the corrective feedback for a tool call that must not be invoked or
      # persisted, or nil if the tool call is acceptable.
      def tool_call_rejection_error(validation, required_tool)
        if required_tool.present? && validation.tool_name != required_tool.tool_name
          return "Error: This iteration required the tool '#{required_tool.tool_name}', but the model called '#{validation.tool_name}' instead."
        end

        case validation.status
        when :unknown_tool
          "Error: Tool '#{validation.tool_name}' is not a valid tool. " \
            "Available tools: #{available_model_tools_map.keys.join(", ")}"
        when :non_hash_arguments, :schema_mismatch, :preparation_error
          "Error: Invalid tool arguments for the tool '#{validation.tool_name}'. " \
            "Tool arguments schema: #{validation.tool_klass.tool_arguments_schema.to_json}. " \
            "Arguments received: #{raw_arguments_excerpt(validation.raw_arguments)}"
        end
      end

      # Echo back what the model sent so it can correct itself (the rejected call is not in
      # history), but cap the excerpt — runaway/truncated argument strings can be enormous.
      def raw_arguments_excerpt(raw_arguments)
        raw = raw_arguments.is_a?(String) ? raw_arguments : JSON.generate(raw_arguments)
        return raw if raw.length <= RAW_ARGUMENTS_EXCERPT_LENGTH

        "#{raw[0, RAW_ARGUMENTS_EXCERPT_LENGTH]} ... (truncated, #{raw.length} characters total)"
      end

      def validate_successful_completion
        return if failed? || final_answer.present?

        fail_run!("Agent completed without calling agent_final_answer")
      end

      def required_tool_warning_message(required_tool)
        if required_tool == final_answer_tool
          if final_iteration?
            I18n.t("raif.agents.native_tool_calling_agent.final_answer_warning")
          else
            "Warning: This iteration requires the agent_final_answer tool. If you do not use it now, the next iteration will be your final chance."
          end
        else
          "Warning: This iteration requires the #{required_tool.tool_name} tool."
        end
      end

      def current_iteration_required_tool
        if @required_tool_iteration_count != iteration_count
          @required_tool_iteration_count = iteration_count
          @current_iteration_required_tool = required_tool_for_iteration
        end

        @current_iteration_required_tool
      end

      def handle_iteration_error(error_content, required_tool: nil)
        error_message = Raif::Messages::UserMessage.new(content: error_content)
        add_conversation_history_entry(error_message.to_h)

        return if required_tool.blank? || retry_iteration_available?

        fail_run!(error_content)
      end

      def retry_iteration_available?
        iteration_count < max_iterations
      end

      def log_required_tool_choice_fallback_once!
        return if @logged_required_tool_choice_fallback

        @logged_required_tool_choice_fallback = true
        Raif.logger.warn(
          "NativeToolCallingAgent is falling back to runtime tool-call validation because #{llm.key} " \
            "cannot faithfully enforce tool_choice: :required for tools: #{available_model_tools_map.keys.join(", ")}"
        )
      end

      def ensure_llm_supports_native_tool_use
        unless llm.supports_native_tool_use?
          errors.add(:base, "Raif::Agent#llm_model_key must use an LLM that supports native tool use")
        end
      end

    end
  end
end
