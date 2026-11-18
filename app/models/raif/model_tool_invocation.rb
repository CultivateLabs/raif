# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_tool_invocations
#
#  id                    :bigint           not null, primary key
#  canceled_at           :datetime
#  completed_at          :datetime
#  completion_mode       :string           default("automatic"), not null
#  deadline_at           :datetime
#  execution_token       :string
#  failed_at             :datetime
#  failure_reason        :text
#  lease_expires_at      :datetime
#  position              :integer
#  result                :jsonb            not null
#  source_type           :string           not null
#  started_at            :datetime
#  tool_arguments        :jsonb            not null
#  tool_type             :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  provider_tool_call_id :string
#  raif_agent_turn_id    :bigint
#  source_id             :bigint           not null
#
# Indexes
#
#  index_raif_model_tool_invocations_on_deadline_at         (deadline_at)
#  index_raif_model_tool_invocations_on_raif_agent_turn_id  (raif_agent_turn_id)
#  index_raif_model_tool_invocations_on_source              (source_type,source_id)
#
class Raif::ModelToolInvocation < Raif::ApplicationRecord
  NO_RESULT = Object.new.freeze
  private_constant :NO_RESULT

  belongs_to :source, polymorphic: true
  belongs_to :raif_agent_turn, class_name: "Raif::AgentTurn", optional: true, inverse_of: :raif_model_tool_invocations

  after_initialize -> { self.tool_arguments ||= {} }
  after_initialize -> { self.result ||= {} }

  validates :tool_type, presence: true
  validate :ensure_valid_tool_argument_schema, if: -> { tool_type.present? && tool_arguments_schema.present? }

  delegate :renderable?,
    :tool_name,
    to: :tool

  # Instance-aware shims so callers (Raif::Conversation, Raif::ConversationEntry,
  # etc.) ask the invocation itself, which forwards `self` to the tool class.
  # Lets tools decide per-invocation rather than at the class level.
  def format_result_for_llm
    tool.format_result_for_llm(self)
  rescue StandardError => e
    # A formatter that raises must not fail the conversation or agent run that was only
    # trying to build a message. Returning nil lets callers fall back to the raw persisted
    # result, which is always sendable.
    Raif.logger.error("Raif::ModelToolInvocation##{id}: #{tool_type} formatter failed: #{e.class}: #{e.message}")
    nil
  end

  def triggers_immediate_llm_follow_up?
    tool.triggers_immediate_llm_follow_up?(self)
  end

  boolean_timestamp :started_at
  boolean_timestamp :completed_at
  boolean_timestamp :failed_at
  boolean_timestamp :canceled_at

  COMPLETION_MODES = ["automatic", "deferred"].freeze

  validates :completion_mode, inclusion: { in: COMPLETION_MODES }

  # Not terminal: the barrier of the owning turn or entry stays closed while any exist.
  scope :unfinished, -> { where(completed_at: nil, failed_at: nil, canceled_at: nil) }
  scope :overdue, ->(now = Time.current) { unfinished.where(arel_table[:deadline_at].lt(now)) }
  scope :in_call_order, -> { order(:position, :id) }

  attr_writer :barrier_owner

  def finished?
    completed_at.present? || failed_at.present? || canceled_at.present?
  end

  def deferred_completion?
    completion_mode == "deferred"
  end

  # The turn or conversation entry that waits for this invocation. nil for an
  # invocation made directly through Raif::ModelTool.invoke_tool.
  def barrier_owner
    return @barrier_owner if defined?(@barrier_owner) && @barrier_owner

    @barrier_owner = raif_agent_turn || (source if position.present? && source.is_a?(Raif::Concerns::ToolBarrier))
  end

  # Runs the tool for this invocation. Safe to call from more than one job:
  # only the caller that wins the claim runs the tool.
  #
  # Raif runs a tool at most once by default. If the process stops while the tool
  # runs, the invocation ends at its deadline with an error result and the model
  # can call the tool again. A tool class that declares `retry_safe` lets a later
  # execution take the invocation over once its lease has expired.
  #
  # @param context_established [Boolean] true when the caller already runs inside
  #   the owner's run context, so the hook is not entered a second time.
  # @param raise_fatal [Boolean] re-raise an error that ends the run (Raif::Agent#run!).
  # @return [Boolean] whether this call ran the tool
  def execute!(context_established: false, raise_fatal: false)
    owner = barrier_owner

    # A queued call of a run that already ended must not start.
    if owner.present? && !owner.barrier_owner_live?
      cancel!
      return false
    end

    token = claim_execution!
    return false if token.nil?

    begin
      if context_established || owner.nil?
        tool.process_invocation(self)
      else
        owner.with_tool_run_context { tool.process_invocation(self) }
      end
    rescue StandardError => e
      handle_execution_error(e, token: token, raise_fatal: raise_fatal)
      return true
    end

    # A deferred invocation stays unfinished until the host calls #complete! or #fail!.
    finish!(execution_token: token) unless deferred_completion?
    owner&.check_tool_barrier!
    true
  end

  # Completes a deferred invocation with its result. Call it from host code when
  # the work the tool started is done. The waiting turn or entry continues once
  # every invocation it dispatched is terminal.
  #
  # @param result [Object] stored as the invocation result (omit to keep a result the host already saved)
  # @return [Boolean] false when the invocation was already terminal (for example its
  #   deadline passed); nothing changes in that case.
  def complete!(result = NO_RESULT)
    return false unless finish!(result: result)

    barrier_owner&.check_tool_barrier!
    true
  end

  # Ends the invocation without a result. The model receives `message` as the error
  # result of the call and the run continues, so write the message for the model.
  #
  # @return [Boolean] false when the invocation was already terminal
  def fail!(message)
    return false unless terminate!(failed_at: Time.current, failure_reason: message.to_s)

    barrier_owner&.check_tool_barrier!
    true
  end

  # Ends an invocation whose deadline passed. The deadline stops the wait: it does
  # not stop tool code or host work that is still running, and a result that
  # arrives later is ignored.
  #
  # @return [Boolean] false when the invocation was already terminal or is not overdue
  def expire!(now: Time.current)
    return false if deadline_at.blank? || deadline_at > now

    reason = "Error: The #{tool_name} tool did not return a result before its deadline. " \
      "Try different arguments or another tool."
    return false unless terminate!(failed_at: now, failure_reason: reason)

    barrier_owner&.check_tool_barrier!
    true
  end

  # Ends an invocation that must not run or count any more (its run failed or was canceled).
  def cancel!
    terminate!(canceled_at: Time.current)
  end

  # Queues the job that ends the invocation if it is still unfinished at its deadline.
  def schedule_deadline_job
    return if deadline_at.blank?

    Raif::ModelToolInvocationDeadlineJob.set(wait_until: deadline_at).perform_later(model_tool_invocation: self)
  end

  # Moves the deadline of an unfinished invocation, for example when the host
  # learns how long the deferred work will take.
  def extend_deadline!(new_deadline_at)
    updated = self.class.unfinished.where(id: id).update_all(deadline_at: new_deadline_at, updated_at: Time.current)
    reload
    return false unless updated == 1

    schedule_deadline_job
    true
  end

  # The error text the model receives for a failed invocation.
  def error_result_for_llm
    failure_reason.presence || "Error: The #{tool_name} tool failed and returned no result."
  end

  def tool
    @tool ||= tool_type.constantize
  end

  # Routes through `tool_arguments_schema_for_source` so the invocation
  # validates against the schema the model saw when making the call. The
  # helper forwards `source:` only to tools whose `tool_arguments_schema`
  # accepts it, keeping existing overrides that predate the keyword working.
  def tool_arguments_schema
    tool.tool_arguments_schema_for_source(source)
  end

  # Returns tool call in the format expected by LLM message formatting
  # @param assistant_message [String, nil] Optional assistant message accompanying the tool call
  # @return [Hash] Hash representation for JSONB storage and LLM APIs
  def as_tool_call_message(assistant_message: nil)
    Raif::Messages::ToolCall.new(
      provider_tool_call_id: provider_tool_call_id,
      name: tool_name,
      arguments: tool_arguments,
      assistant_message: assistant_message
    ).to_h
  end

  # Returns tool result in the format expected by LLM message formatting
  # @return [Hash] Hash representation for JSONB storage and LLM APIs
  def as_tool_call_result_message(result: self.result)
    Raif::Messages::ToolCallResult.new(
      provider_tool_call_id: provider_tool_call_id,
      name: tool_name,
      result: result
    ).to_h
  end

  def to_partial_path
    "raif/model_tool_invocations/#{tool.invocation_partial_name}"
  end

  def admin_formatted_result
    admin_formatted_result_attempt[:formatted]
  end

  def admin_formatted_result_error
    admin_formatted_result_attempt[:error]
  end

  # True when admin should show the formatted result block — either we have
  # something to display (the formatted payload or its raw-result fallback) or
  # we have a formatter error to surface.
  def admin_formatted_result_available?
    admin_formatted_result.present? || admin_formatted_result_error.present?
  end

  def ensure_valid_tool_argument_schema
    unless JSON::Validator.validate(tool_arguments_schema, tool_arguments)
      errors.add(:tool_arguments, "does not match schema")
    end
  end

private

  # Claims the invocation for one execution. Returns the execution token, or nil
  # when another execution holds the claim.
  def claim_execution!
    token = SecureRandom.hex(16)
    now = Time.current
    lease_expires_at = now + tool.execution_lease
    claim = { started_at: now, execution_token: token, lease_expires_at: lease_expires_at, updated_at: now }

    claimed = self.class.unfinished.where(id: id, started_at: nil).update_all(claim)

    # Takeover of an abandoned execution, for tools that declared it safe.
    if claimed.zero? && tool.retry_safe?
      claimed = self.class.unfinished.where(id: id).where(self.class.arel_table[:lease_expires_at].lt(now)).update_all(claim)
    end

    return if claimed.zero?

    # Keep attributes the tool may read, without discarding anything in memory.
    self.started_at = now
    self.execution_token = token
    self.lease_expires_at = lease_expires_at
    clear_attribute_changes([:started_at, :execution_token, :lease_expires_at])
    token
  end

  # Marks the invocation completed, unless it is already terminal or another
  # execution took it over. Persists a result the tool set in memory.
  def finish!(result: NO_RESULT, execution_token: nil)
    transaction do
      current = self.class.lock.find(id)
      next false if current.finished?
      next false if execution_token.present? && current.execution_token != execution_token

      self.result = result unless result.equal?(NO_RESULT)
      self.completed_at = Time.current
      # Skip validation: a source-aware schema can change during the run, and a
      # silently failed write would leave the barrier closed forever.
      save!(validate: false)
      true
    end
  end

  def terminate!(attributes)
    updated = self.class.unfinished.where(id: id).update_all(attributes.merge(updated_at: Time.current))
    reload
    updated == 1
  end

  def handle_execution_error(error, token:, raise_fatal:)
    owner = barrier_owner

    if owner.nil?
      terminate!(failed_at: Time.current, failure_reason: error.message)
      raise error
    end

    if owner.recoverable_tool_error?(error)
      owner.report_tool_error(self, error)
      self.class.unfinished.where(id: id, execution_token: token).update_all(
        failed_at: Time.current,
        failure_reason: owner.tool_error_message_for_model(self, error),
        updated_at: Time.current
      )
      reload
      owner.check_tool_barrier!
    else
      terminate!(failed_at: Time.current, failure_reason: error.message)
      owner.fail_from_tool_error!(self, error)
      raise error if raise_fatal

      owner.report_tool_error(self, error)
    end
  end

  # Best-effort reconstruction of the formatted result shown in admin. Uses the
  # current formatter code against persisted invocation data, so formatter
  # failures are captured for display instead of breaking the page render.
  # Mirrors `Raif::Conversation#tool_result_for_llm`'s fallback to the raw
  # `result` so admin shows what was actually sent to the model.
  def admin_formatted_result_attempt
    @admin_formatted_result_attempt ||= if completed?
      begin
        formatted = tool.format_result_for_llm(self)
        { formatted: formatted.presence || result, error: nil }
      rescue StandardError => e
        { formatted: nil, error: e.message }
      end
    else
      { formatted: nil, error: nil }
    end
  end

end
