# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_conversation_entries
#
#  id                     :bigint           not null, primary key
#  citations              :jsonb
#  completed_at           :datetime
#  creator_type           :string           not null
#  execution_context      :jsonb
#  failed_at              :datetime
#  finalized_at           :datetime
#  llm_model_key          :string
#  model_response_message :text
#  raw_response           :text
#  started_at             :datetime
#  tools_completed_at     :datetime
#  tools_dispatched_at    :datetime
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
#  index_raif_conversation_entries_on_tools_dispatched_at   (tools_dispatched_at)
#
# Foreign Keys
#
#  fk_rails_...  (raif_conversation_id => raif_conversations.id)
#
class Raif::ConversationEntry < Raif::ApplicationRecord
  include Raif::Concerns::InvokesModelTools
  include Raif::Concerns::HasAvailableModelTools
  include Raif::Concerns::ToolCallValidation
  include Raif::Concerns::ToolBarrier

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
  # citations and llm_model_key are denormalized local columns (copied from
  # the winning completion in finalize_entry!) so they survive culling of old
  # completion rows. system_prompt stays delegated: it's admin-only debugging
  # and too large to be worth denormalizing.
  delegate :system_prompt, to: :raif_model_completion, allow_nil: true

  accepts_nested_attributes_for :raif_user_tool_invocation

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at

  after_initialize -> { self.citations ||= [] }
  after_initialize -> { self.execution_context = {} if execution_context.nil? }, if: :new_record?
  validate :execution_context_is_an_object

  before_validation :add_user_tool_invocation_to_user_message, on: :create
  after_create_commit :update_conversation_latest_entry_at

  normalizes :model_response_message, with: ->(value) { value&.strip }
  normalizes :user_message, with: ->(value) { value&.strip }

  # One-time backfill for entries created before citations/llm_model_key were
  # denormalized onto this table (see the
  # raif:backfill_conversation_entry_completion_fields rake task). Copies from
  # the newest model completion via update_columns, skipping callbacks and
  # updated_at on historical rows. Idempotent: entries that already have both
  # fields populated fall out of the scope. Entries with no completion are
  # left untouched.
  def self.backfill_denormalized_completion_fields!(batch_size: 500)
    where("citations IS NULL OR llm_model_key IS NULL")
      .includes(:raif_model_completion)
      .find_each(batch_size: batch_size) do |entry|
        completion = entry.raif_model_completion
        next if completion.nil?

        entry.update_columns(
          citations: completion.citations,
          llm_model_key: completion.llm_model_key
        )
      end
  end

  def execution_context_is_an_object
    return if persisted? && execution_context.nil? && !will_save_change_to_execution_context?

    errors.add(:execution_context, :invalid) unless execution_context.is_a?(Hash)
  end

  def add_user_tool_invocation_to_user_message
    return unless raif_user_tool_invocation.present?

    self.user_message = [user_message, raif_user_tool_invocation.as_user_message].join("\n\n")
  end

  def update_conversation_latest_entry_at
    raif_conversation.update_column(:latest_entry_at, created_at)
  end

  def response_format
    raif_model_completion&.response_format.presence || raif_conversation.response_format
  end

  def generating_response?
    started? && !completed? && !failed?
  end

  # True while the entry waits for its tool calls to end. The model response is
  # saved; the entry completes when every call is terminal. No model call
  # happens while it waits.
  def waiting_on_tools?
    tools_dispatched_at.present? && tools_completed_at.blank? && !failed?
  end

  # The entry's tool invocations in the order the model made the calls. The
  # calls of one entry run concurrently, so row order is not call order. A
  # canceled call belongs to a failed entry and is left out.
  def tool_invocations_in_call_order
    raif_model_tool_invocations.reject(&:canceled?).sort_by { |invocation| [invocation.position || 0, invocation.id] }
  end

  # The tool invocations the entry is waiting for.
  def pending_tool_invocations
    return Raif::ModelToolInvocation.none unless waiting_on_tools?

    raif_model_tool_invocations.unfinished.in_call_order
  end

  # Generate a model response for this entry, validating any returned
  # developer-managed tool calls and re-prompting with synthetic corrective
  # feedback when validation fails. Bounded by
  # {Raif.config.conversation_entry_max_retries}.
  def process_entry!
    within_run_context { generate_response! }
  end

  # Restarts whatever an entry that dispatched tool calls still owes: tool jobs
  # that were never queued, a barrier check that never ran, or the continuation
  # after the barrier. Every part is safe to repeat. Called by
  # Raif::RecoverStalledRunsJob.
  def recover_tool_calls!
    return if tools_dispatched_at.blank? || failed? || finalized_at.present?

    touch
    if completed?
      continue_after_tools!
    else
      within_run_context { run_tool_invocations!(run_inline: false) }
    end
  end

  # --- Raif::Concerns::ToolBarrier ---

  def barrier_lock(&block)
    with_lock(&block)
  end

  def awaiting_tool_results?
    waiting_on_tools? && !completed?
  end

  def barrier_owner_live?
    !reload.failed?
  end

  def barrier_tool_invocations
    raif_model_tool_invocations
  end

  # The entry becomes completed here, so the conversation's next model request
  # includes its tool results. The continuation is recorded separately in
  # finalized_at.
  def close_tool_barrier!
    now = Time.current
    update_columns(tools_completed_at: now, completed_at: now, updated_at: now)
  end

  # Runs what follows a completed entry: the conversation's on_entry_finalized
  # hook, the follow-up entry and the UI update. The row lock lets only one
  # caller run it (the barrier and a recovery sweep can overlap). Repeatable
  # until finalized_at commits, so a crash in here is recovered; the hook can
  # then run a second time.
  def continue_after_tools!
    continued = with_lock do
      next false unless completed? && tools_dispatched_at.present? && finalized_at.blank?

      within_run_context { finalize_completed_entry! }
      update_columns(finalized_at: Time.current)
      true
    end

    broadcast_entry_processed if continued
  end

  def with_tool_run_context(&block)
    within_run_context(&block)
  end

  # Enters the conversation's #with_run_context unless this process is already
  # inside it for this entry, so the host context is not entered a second time.
  def within_run_context
    return yield if @within_run_context

    begin
      @within_run_context = true
      raif_conversation.with_run_context(entry: self) { yield }
    ensure
      @within_run_context = false
    end
  end

  # A tool exception fails the entry, as it always has. A deadline or a host
  # `fail!` is different: the entry completes and the model sees an error result.
  def recoverable_tool_error?(_error)
    false
  end

  def tool_error_message_for_model(invocation, _error)
    invocation.error_result_for_llm
  end

  def report_tool_error(invocation, error)
    logger.error "Error processing conversation entry ##{id}. Error: #{error.message}"
    logger.error error.backtrace.join("\n") if error.backtrace.present?
    Rails.error.report(error, handled: true, severity: :error, context: {
      component: "raif_conversation_entry",
      action: "invoke_tool",
      conversation_entry_id: id,
      tool_name: invocation.tool_name
    })
  end

  # The caller holds the entry's lock and runs #after_failed_from_tool_error
  # after it returns true.
  def fail_from_tool_error!(_invocation, _error)
    with_lock do
      next false if failed? || completed?

      now = Time.current
      update_columns(failed_at: now, updated_at: now)
      raif_model_tool_invocations.unfinished.where(started_at: nil).update_all(canceled_at: now, updated_at: now)
      true
    end
  end

  def after_failed_from_tool_error
    raif_conversation.update_columns(generating_entry_response: false)
    broadcast_entry_processed
  end

  # True when at least one of this entry's tool invocations wants the model to
  # be prompted again immediately in a follow-up turn — used to drive the
  # synthetic next entry created by {#create_immediate_follow_up_entry!}.
  def triggers_immediate_llm_follow_up?
    return false unless completed?

    # A call that ended without a result (its deadline passed, or the host failed
    # it) always goes back to the model, so it can tell the user or try again.
    # Read through the barrier's current rows: on MySQL a plain read can miss a
    # call that another transaction failed just before the barrier opened.
    invocations = Raif::Concerns::ToolBarrier.current_rows(raif_model_tool_invocations).to_a
    invocations.any? { |invocation| invocation.failed? || invocation.triggers_immediate_llm_follow_up? }
  end

  def create_immediate_follow_up_entry!
    follow_up_entry = raif_conversation.entries.create!(creator: creator)
    Raif::ApplicationJob.after_transaction_commit { Raif::ConversationEntryJob.perform_later(conversation_entry: follow_up_entry) }
    follow_up_entry.broadcast_append_to raif_conversation, target: ActionView::RecordIdentifier.dom_id(raif_conversation, :entries)
  end

private

  def generate_response!
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

  # Saves the winning response and creates one invocation row per tool call.
  # An entry without tool calls completes here. An entry with tool calls waits
  # behind its barrier: each call runs (in this job when there is only one,
  # otherwise in a job of its own) and the entry completes when the last one ends.
  def finalize_entry!(model_completion:, validations:)
    invocations = []

    transaction do
      self.raw_response = model_completion.raw_response
      self.model_response_message = raif_conversation.process_model_response_message(
        message: model_completion.parsed_response,
        entry: self
      )
      # Copy from the winning (not retried) completion so these survive
      # culling of old completion rows. Runs once per finalized entry, after
      # retry attempts resolve; all provider adapter paths (including
      # streaming) have set citations on the in-memory completion by now.
      self.citations = model_completion.citations
      self.llm_model_key = model_completion.llm_model_key
      save!

      tool_calls = model_completion.response_tool_calls || []
      tool_calls.each_with_index do |tool_call, index|
        validation = validations[index]
        next if validation&.tool_klass.nil?

        invocation = validation.tool_klass.build_invocation(
          provider_tool_call_id: tool_call["provider_tool_call_id"],
          tool_arguments: validation.prepared_arguments,
          source: self,
          position: index
        )
        invocation.deadline_at = Time.current + invocation.tool.invocation_deadline
        invocation.save!
        invocations << invocation
      end

      if invocations.empty?
        completed!
      else
        update!(tools_dispatched_at: Time.current)
      end
    end

    if invocations.empty?
      finalize_completed_entry!
    else
      # The conversation stays in its "generating" state until the barrier opens.
      raif_conversation.update_columns(generating_entry_response: true)
      invocations.each(&:schedule_deadline_job)
      run_tool_invocations!
    end
  rescue StandardError => e
    # Do not re-raise: the caller is ConversationEntryJob via Sidekiq and we
    # don't want the job to retry on top of our in-process retry budget. Mark
    # the entry failed so the UI surfaces the error and move on.
    logger.error "Error processing conversation entry ##{id}. Error: #{e.message}"
    logger.error e.backtrace.join("\n")
    failed! unless failed?
    # The dispatch above set the generating flag again; a failed entry must clear it.
    raif_conversation.update_columns(generating_entry_response: false) if raif_conversation.generating_entry_response?
  end

  # Starts every tool call that has not started, then checks the barrier.
  #
  # @param run_inline [Boolean] run a single call in this process. Recovery passes
  #   false, so a slow tool does not hold up the sweep.
  def run_tool_invocations!(run_inline: true)
    invocations = raif_model_tool_invocations.in_call_order.to_a
    startable = invocations.reject(&:finished?).select { |invocation| invocation.started_at.blank? || invocation.tool.retry_safe? }

    # One call gains nothing from a job of its own, so it runs right here.
    if run_inline && invocations.one?
      startable.each do |invocation|
        invocation.barrier_owner = self
        invocation.execute!(context_established: true)
      end
    else
      queue = Raif.config.model_tool_invocation_job_queue
      job = queue.present? ? Raif::ModelToolInvocationJob.set(queue: queue) : Raif::ModelToolInvocationJob
      Raif::ApplicationJob.after_transaction_commit do
        startable.each { |invocation| job.perform_later(model_tool_invocation: invocation) }
      end
    end

    check_tool_barrier!
  end

  # Fire the post-finalize hook once the entry is completed, outside any
  # transaction, so that persistent side-effect code in subclasses (e.g.
  # creating dependent records, broadcasting UI updates) never runs for
  # discarded retry attempts. See {Raif::Conversation#on_entry_finalized}.
  def finalize_completed_entry!
    raif_conversation.update_columns(generating_entry_response: false) if raif_conversation.generating_entry_response?
    raif_conversation.on_entry_finalized(entry: self)

    create_immediate_follow_up_entry! if triggers_immediate_llm_follow_up?
  rescue StandardError => e
    logger.error "Error processing conversation entry ##{id}. Error: #{e.message}"
    logger.error e.backtrace.join("\n")
    failed! unless failed?
  end

  # The entry's state is already saved, so a failed UI update is reported and
  # must not undo or fail anything.
  def broadcast_entry_processed
    conversation = raif_conversation
    Turbo::StreamsChannel.broadcast_render_to conversation,
      partial: "raif/conversations/entry_processed",
      locals: { conversation: conversation, conversation_entry: self }
  rescue StandardError => e
    logger.error "Error broadcasting conversation entry ##{id}. Error: #{e.message}"
    Rails.error.report(e, handled: true, severity: :warning, context: {
      component: "raif_conversation_entry",
      action: "broadcast_entry_processed",
      conversation_entry_id: id
    })
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
