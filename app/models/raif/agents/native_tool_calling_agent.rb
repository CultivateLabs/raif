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
        step_two = if self.class.parallel_tool_calls
          "Choose and invoke one or more tool/function calls based on that thought. You may make several " \
            "independent tool calls in a single step; when a call depends on another's result, make them in separate steps."
        else
          "Choose and invoke exactly one tool/function call based on that thought."
        end

        final_answer_note = if self.class.parallel_tool_calls
          "\n- Call the agent_final_answer tool by itself - do not combine it with other tool calls in the same step."
        else
          ""
        end

        <<~PROMPT.strip
          You are an AI agent that follows the ReAct (Reasoning + Acting) framework to complete tasks step by step using tool/function calls.

          At each step, you must:
          1. Think about what to do next.
          2. #{step_two}
          3. Observe the results of the tool/function call(s).
          4. Use the results to update your thought process.
          5. Repeat steps 1-4 until the task is complete.
          6. Provide a final answer to the user's request.

          For your final answer:
          - You **MUST** use the agent_final_answer tool/function to provide your final answer.#{final_answer_note}
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

        # The response was cut off at the provider's max output token limit. Any tool calls
        # in it cannot be trusted (their arguments may be truncated mid-JSON), so they are
        # never invoked or persisted. Any assistant text is kept for context - the follow-up
        # error message tells the model it was cut off and lets it retry.
        if model_completion.truncated?
          error_content = "Error: Your previous response exceeded the maximum output length and was cut off before completing. " \
            "Keep your responses and tool call arguments concise. Avoid very long queries or long, repetitive lists in arguments. " \
            "Prefer multiple smaller tool calls."
          reject_iteration!(error_content, assistant_response_message, required_tool:)

          return
        end

        # The model made no tool call in this completion. Tell it to make a tool call.
        if model_completion.response_tool_calls.blank?
          error_content = if required_tool.present?
            "Error: This iteration required the tool '#{required_tool.tool_name}', but the model response contained no tool call. Available tools: #{available_model_tools_map.keys.join(", ")}" # rubocop:disable Layout/LineLength
          else
            "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: #{available_model_tools_map.keys.join(", ")}" # rubocop:disable Layout/LineLength
          end
          reject_iteration!(error_content, assistant_response_message, required_tool:)

          return
        end

        tool_calls = model_completion.response_tool_calls

        # Parallel tool calls disabled (agent class opted out, or the model doesn't
        # support them): only one call per step.
        if tool_calls.length > 1 && !parallel_tool_calls_allowed?
          error_content = "Error: Multiple tool calls received. Only one tool call is allowed per step. " \
            "Please call exactly one tool at a time."
          reject_iteration!(error_content, assistant_response_message, required_tool:)

          return
        end

        # Guard against pathological fan-out (and runaway context/cost) in a single step.
        max_calls = self.class.max_tool_calls_per_iteration
        if max_calls.present? && tool_calls.length > max_calls
          error_content = "Error: Too many tool calls in a single step (received #{tool_calls.length}). " \
            "Make at most #{max_calls} tool call#{"s" unless max_calls == 1} per step."
          reject_iteration!(error_content, assistant_response_message, required_tool:)

          return
        end

        validations = tool_calls.map { |tool_call| validate_tool_call(tool_call, available_model_tools_map, source: self) }

        # When the model calls agent_final_answer alongside other tools, honor the final
        # answer and drop the siblings without invoking them. Invoking a sibling here would
        # record results/documents the model never actually observed before answering.
        final_answer_index = validations.index { |validation| validation.tool_name == "agent_final_answer" }
        if final_answer_index && tool_call_rejection_error(validations[final_answer_index], required_tool).nil?
          tool_calls = [tool_calls[final_answer_index]]
          validations = [validations[final_answer_index]]
        else
          # Atomic validation: if any call is invalid, none are invoked or persisted. A
          # rejected call replayed to the provider on the next request would be rejected
          # (no paired tool result), so we keep any assistant text and send corrective
          # feedback covering every invalid call instead.
          rejection_error = batch_rejection_error(validations, required_tool)
          if rejection_error.present?
            reject_iteration!(rejection_error, assistant_response_message, required_tool:)

            return
          end
        end

        # Invoke each valid call in order, interleaving its result with the call so the
        # provider sees correctly paired tool_call/tool_call_result messages on replay.
        # Only the first call carries the assistant's prose for this turn.
        tool_calls.each_with_index do |tool_call, index|
          validation = validations[index]

          tool_call_message = Raif::Messages::ToolCall.new(
            provider_tool_call_id: tool_call["provider_tool_call_id"],
            name: tool_call["name"],
            arguments: validation.prepared_arguments,
            assistant_message: (index.zero? ? assistant_response_message : nil),
            provider_metadata: tool_call["provider_metadata"]
          )
          add_conversation_history_entry(tool_call_message.to_h)

          tool_invocation = validation.tool_klass.invoke_tool(
            provider_tool_call_id: tool_call["provider_tool_call_id"],
            tool_arguments: validation.prepared_arguments,
            source: self
          )

          if validation.tool_name == "agent_final_answer"
            self.final_answer = tool_invocation.result
            break
          else
            add_conversation_history_entry(tool_invocation.as_tool_call_result_message)
          end
        end
      end

      # Permit parallel tool calls unless they're disallowed, or this iteration forces a
      # specific tool (e.g. the final-answer iteration), where exactly one call is required.
      def allow_parallel_tool_calls?
        parallel_tool_calls_allowed? && current_iteration_required_tool.nil?
      end

      # Whether this agent class and its LLM both permit multiple tool calls per iteration.
      def parallel_tool_calls_allowed?
        self.class.parallel_tool_calls && llm.supports_parallel_tool_calls?
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
          # Echo the same schema the validation actually ran against (tools can define
          # source-aware schemas), plus the validator's errors when it produced any.
          error = "Error: Invalid tool arguments for the tool '#{validation.tool_name}'. " \
            "Tool arguments schema: #{validation.tool_klass.tool_arguments_schema_for_source(self).to_json}. " \
            "Arguments received: #{raw_arguments_excerpt(validation.raw_arguments)}"
          error += ". Validation errors: #{feedback_excerpt(Array(validation.errors).join("; "))}" if validation.errors.present?
          error
        end
      end

      # Aggregated corrective feedback for a batch of tool calls, or nil if all are
      # acceptable. A single invalid call returns its error verbatim (matching the
      # single-call path); multiple invalid calls are summarized, then listed.
      def batch_rejection_error(validations, required_tool)
        errors = validations.filter_map { |validation| tool_call_rejection_error(validation, required_tool) }
        return if errors.empty?
        return errors.first if errors.length == 1

        header = "Error: #{errors.length} of the #{validations.length} tool calls in your previous response were invalid. " \
          "None were executed. Correct them and try again - you may call multiple tools in one step."
        [header, *errors].join("\n\n")
      end

      # Echo back what the model sent so it can correct itself (the rejected call is not in
      # history), but cap the excerpt — runaway/truncated argument strings can be enormous.
      def raw_arguments_excerpt(raw_arguments)
        feedback_excerpt(raw_arguments.is_a?(String) ? raw_arguments : JSON.generate(raw_arguments))
      end

      # Cap text echoed back to the model in corrective feedback.
      def feedback_excerpt(text)
        return text if text.length <= RAW_ARGUMENTS_EXCERPT_LENGTH

        "#{text[0, RAW_ARGUMENTS_EXCERPT_LENGTH]} ... (truncated, #{text.length} characters total)"
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

      # A completion whose tool calls can't be used (truncated, missing, multiple, or
      # rejected). Keeps any assistant text for context, never persists the tool calls,
      # and feeds corrective feedback back to the model via handle_iteration_error
      # (which fails the run when no retry is available).
      def reject_iteration!(error_content, assistant_response_message, required_tool:)
        if assistant_response_message.present?
          assistant_message = Raif::Messages::AssistantMessage.new(content: assistant_response_message)
          add_conversation_history_entry(assistant_message.to_h)
        end

        handle_iteration_error(error_content, required_tool:)
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
