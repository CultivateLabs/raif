# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_conversation_entries
#
#  id                     :bigint           not null, primary key
#  completed_at           :datetime
#  creator_type           :string           not null
#  failed_at              :datetime
#  model_response_message :text
#  raw_response           :text
#  started_at             :datetime
#  user_message           :text
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  raif_conversation_id   :bigint           not null
#
# Indexes
#
#  index_raif_conversation_entries_on_created_at            (created_at)
#  index_raif_conversation_entries_on_creator               (creator_type,creator_id)
#  index_raif_conversation_entries_on_raif_conversation_id  (raif_conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (raif_conversation_id => raif_conversations.id)
#
class Raif::ConversationEntry < Raif::ApplicationRecord
  include Raif::Concerns::InvokesModelTools
  include Raif::Concerns::HasAvailableModelTools
  include Raif::Concerns::ToolCallValidation

  belongs_to :raif_conversation, counter_cache: true, class_name: "Raif::Conversation"
  belongs_to :creator, polymorphic: true

  has_one :raif_user_tool_invocation,
    class_name: "Raif::UserToolInvocation",
    dependent: :destroy,
    foreign_key: :raif_conversation_entry_id,
    inverse_of: :raif_conversation_entry

  # All model completions for this entry, in attempt order (oldest first). The
  # retry loop in {#process_entry!} can produce multiple rows per entry.
  has_many :raif_model_completions,
    -> { order(created_at: :asc) },
    as: :source,
    dependent: :destroy,
    class_name: "Raif::ModelCompletion"

  # Convenience accessor returning the newest (i.e. most recently attempted)
  # model completion. Existing callers that expect a single completion per
  # entry continue to resolve to the latest attempt. Destruction is handled
  # by the `has_many` association above, so this one does not declare a
  # `dependent:` option.
  has_one :raif_model_completion,
    -> { order(created_at: :desc) },
    as: :source,
    class_name: "Raif::ModelCompletion",
    inverse_of: :source

  delegate :available_model_tools, to: :raif_conversation
  delegate :system_prompt, :llm_model_key, :citations, to: :raif_model_completion, allow_nil: true

  accepts_nested_attributes_for :raif_user_tool_invocation

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  before_validation :add_user_tool_invocation_to_user_message, on: :create

  normalizes :model_response_message, with: ->(value) { value&.strip }
  normalizes :user_message, with: ->(value) { value&.strip }

  def add_user_tool_invocation_to_user_message
    return unless raif_user_tool_invocation.present?

    self.user_message = [user_message, raif_user_tool_invocation.as_user_message].join("\n\n")
  end

  def response_format
    raif_model_completion&.response_format.presence || raif_conversation.response_format
  end

  def generating_response?
    started? && !completed? && !failed?
  end

  # Generate a model response for this entry, validating any returned
  # developer-managed tool calls and re-prompting with synthetic corrective
  # feedback when validation fails. Bounded by
  # {Raif.config.conversation_entry_max_retries}.
  def process_entry!
    self.model_response_message = ""
    extra_messages = []
    retries_remaining = Raif.config.conversation_entry_max_retries.to_i

    loop do
      model_completion = prompt_for_attempt(extra_messages: extra_messages)

      # prompt_model_for_entry_response rescues infrastructure errors and
      # marks the entry failed itself. Nothing more to do here.
      return self if failed?

      unless model_completion.present? && (model_completion.parsed_response.present? || model_completion.response_tool_calls.present?)
        logger.error "Error processing conversation entry ##{id}. No model response found."
        failed!
        return self
      end

      tool_calls = model_completion.response_tool_calls || []
      validations = tool_calls.map { |tc| validate_tool_call(tc, available_model_tools_map, source: self) }
      invalid_validations = validations.reject(&:ok?)

      if invalid_validations.empty?
        finalize_entry!(model_completion: model_completion, validations: validations)
        return self
      end

      if retries_remaining <= 0
        log_tool_call_failure(model_completion, invalid_validations)
        failed!
        return self
      end

      retries_remaining -= 1
      extra_messages.concat(build_retry_messages(model_completion, validations))
    end
  rescue StandardError => e
    # Defensive: anything thrown out of the retry loop (e.g. an unexpected
    # error in parsed_response, feedback construction, or a downstream tool
    # invocation that escapes finalize_entry!'s own rescue) must still leave
    # the entry in a terminal state so the UI doesn't render
    # `generating_response?` forever.
    logger.error "Error processing conversation entry ##{id}. Error: #{e.message}"
    logger.error e.backtrace.join("\n")
    failed! unless failed?
    self
  end

  def triggers_observation_to_model?
    return false unless completed?

    raif_model_tool_invocations.any?(&:triggers_observation_to_model?)
  end

  def create_entry_for_observation!
    follow_up_entry = raif_conversation.entries.create!(creator: creator)
    Raif::ConversationEntryJob.perform_later(conversation_entry: follow_up_entry)
    follow_up_entry.broadcast_append_to raif_conversation, target: ActionView::RecordIdentifier.dom_id(raif_conversation, :entries)
  end

private

  def prompt_for_attempt(extra_messages:)
    raif_conversation.prompt_model_for_entry_response(entry: self, extra_messages: extra_messages) do |model_completion, _delta, _sse_event|
      self.raw_response = model_completion.raw_response
      self.model_response_message = raif_conversation.process_model_response_message(
        message: model_completion.parsed_response(force_reparse: true),
        entry: self
      )

      update_columns(
        model_response_message: model_response_message,
        raw_response: raw_response,
        updated_at: Time.current
      )

      broadcast_replace_to raif_conversation
    end
  end

  def finalize_entry!(model_completion:, validations:)
    transaction do
      self.raw_response = model_completion.raw_response
      self.model_response_message = raif_conversation.process_model_response_message(
        message: model_completion.parsed_response,
        entry: self
      )
      save!

      tool_calls = model_completion.response_tool_calls || []
      tool_calls.each_with_index do |tool_call, index|
        validation = validations[index]
        next if validation&.tool_klass.nil?

        validation.tool_klass.invoke_tool(
          provider_tool_call_id: tool_call["provider_tool_call_id"],
          tool_arguments: validation.prepared_arguments,
          source: self
        )
      end

      completed!
    end

    # Fire post-finalize hook once, outside the transaction, so that
    # persistent side-effect code in subclasses (e.g. creating dependent
    # records, broadcasting UI updates) never runs for discarded retry
    # attempts. See {Raif::Conversation#on_entry_finalized}.
    raif_conversation.on_entry_finalized(entry: self)

    create_entry_for_observation! if triggers_observation_to_model?
  rescue StandardError => e
    # Do not re-raise: the caller is ConversationEntryJob via Sidekiq and we
    # don't want the job to retry on top of our in-process retry budget. Mark
    # the entry failed so the UI surfaces the error and move on.
    logger.error "Error processing conversation entry ##{id}. Error: #{e.message}"
    logger.error e.backtrace.join("\n")
    failed! unless failed?
  end

  # Build the in-memory messages appended to the next attempt's LLM request.
  #
  # We deliberately do NOT replay the invalid ToolCall back to the provider.
  # Providers round-trip tool arguments as JSON objects, and echoing a
  # malformed string (the exact failure mode we're trying to correct) can
  # cause the provider to reject the whole request before the model ever
  # sees the corrective feedback. Instead, we send a single user-role
  # synthetic message that quotes the raw arguments verbatim inside the
  # prose — safe for any provider, and sufficient context for the model to
  # correct its next attempt.
  def build_retry_messages(_model_completion, validations)
    [
      Raif::Messages::UserMessage.new(
        content: build_synthetic_feedback_content(validations)
      ).to_h
    ]
  end

  # Build a single user-role feedback string covering every invalid tool call
  # from this attempt. Includes tool name, specific failure reason, raw
  # arguments payload, schema (for known tools only), the list of available
  # tool names, and an instruction on how to proceed.
  #
  # Intentionally omits tool descriptions — some applications configure
  # confidentiality rules that forbid exposing tool descriptions in model
  # context. Tool names alone are enough to let the model correct an
  # unknown-tool-name mistake.
  def build_synthetic_feedback_content(validations)
    invalid = validations.reject(&:ok?)

    lines = []
    lines << "Your previous response contained #{invalid.length} invalid tool call(s). " \
      "Do not repeat the same mistake. Correct the tool call(s) below, or answer the user directly without a tool call if none is needed."

    invalid.each_with_index do |v, i|
      lines << ""
      lines << "Invalid tool call ##{i + 1}: '#{v.tool_name}'"
      lines << "Reason: #{describe_validation_failure(v)}"
      lines << "Raw arguments received: #{format_raw_arguments(v.raw_arguments)}"

      if v.tool_klass.present?
        lines << "Expected arguments schema for '#{v.tool_name}':"
        lines << JSON.pretty_generate(v.tool_klass.tool_arguments_schema)
      end
    end

    lines << ""
    lines << "Available tools: #{available_model_tools_map.keys.join(", ")}"
    lines << ""
    lines << "Retry with corrected tool call(s), or respond directly if no tool is needed."

    lines.join("\n")
  end

  def describe_validation_failure(validation)
    case validation.status
    when :unknown_tool
      "Tool '#{validation.tool_name}' is not a valid/available tool."
    when :non_hash_arguments
      "The arguments for '#{validation.tool_name}' could not be parsed into a JSON object. " \
        "Arguments must be a well-formed JSON object matching the schema."
    when :schema_mismatch
      "The arguments for '#{validation.tool_name}' did not satisfy the schema. " \
        "Validation errors: #{Array(validation.errors).join("; ")}"
    when :preparation_error
      "The arguments for '#{validation.tool_name}' could not be prepared for invocation: " \
        "#{Array(validation.errors).join("; ")}"
    else
      "Unknown validation failure: #{validation.status}"
    end
  end

  def format_raw_arguments(raw_arguments)
    case raw_arguments
    when Hash, Array
      JSON.pretty_generate(raw_arguments)
    else
      raw_arguments.inspect
    end
  end

  def log_tool_call_failure(model_completion, invalid_validations)
    details = invalid_validations.map do |v|
      "{tool=#{v.tool_name.inspect} status=#{v.status} raw_arguments=#{v.raw_arguments.inspect} " \
        "errors=#{Array(v.errors).inspect}}"
    end.join(", ")

    logger.error(
      "Raif::ConversationEntry ##{id} failed after exhausting " \
        "conversation_entry_max_retries=#{Raif.config.conversation_entry_max_retries} retries. " \
        "ModelCompletion ##{model_completion.id} returned invalid tool calls: #{details}"
    )
  end

end
