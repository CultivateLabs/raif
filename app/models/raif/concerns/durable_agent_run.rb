# frozen_string_literal: true

# The agent run as a persisted state machine.
#
# A run is a sequence of Raif::AgentTurn rows. Each turn requests one model
# completion, dispatches the tool calls in it, waits until all of them are
# terminal, and then opens the next turn. Every step reads the saved state
# first, so any step can run again after a crash or a duplicate job delivery.
#
# There is one implementation and two ways to drive it:
#
#   agent.run_later!   One job per turn and one job per tool call. No job holds a
#                      worker for the whole run, and the run survives a deploy.
#   agent.run!         Performs the same steps in the calling process and returns
#                      the final answer. For specs, the console, and callers that
#                      need the answer before they continue.
module Raif::Concerns::DurableAgentRun
  extend ActiveSupport::Concern

  RUN_MODES = ["in_process", "async"].freeze

  included do
    has_many :turns,
      -> { order(:iteration) },
      class_name: "Raif::AgentTurn",
      foreign_key: :raif_agent_id,
      inverse_of: :raif_agent,
      dependent: :destroy

    boolean_timestamp :canceled_at

    # Started and not over.
    scope :in_progress, -> { where.not(started_at: nil).where(completed_at: nil, failed_at: nil, canceled_at: nil) }
    # In progress, with a turn that waits for its tool calls to end.
    scope :waiting, -> { in_progress.where(id: Raif::AgentTurn.where(status: "tools_dispatched").select(:raif_agent_id)) }

    # Queues for this agent class's turn jobs and tool jobs. nil uses
    # Raif.config.agent_turn_job_queue / Raif.config.model_tool_invocation_job_queue.
    class_attribute :turn_job_queue, instance_writer: false, default: nil
    class_attribute :tool_invocation_job_queue, instance_writer: false, default: nil
  end

  # Runs the agent in the calling process and returns the final answer.
  #
  # If a block is given, it is called with each entry added to the agent's
  # conversation history. The entries of one turn are added together, once all
  # of the turn's tool calls have ended, so a tool call entry arrives with its
  # result. Override #after_tool_calls_dispatched to react when calls start.
  #
  #   agent.run! do |conversation_history_entry|
  #     Turbo::StreamsChannel.broadcast_append_to(:my_agent_channel, ...)
  #   end
  #
  # An agent with a tool that defers completion cannot run in process, because
  # nothing here can wait for the host: use #run_later!.
  #
  # @return [String, nil] the final answer
  def run!(&block)
    self.on_conversation_history_entry = block_given? ? block : nil
    start_run!("in_process")

    until run_over?
      turn = current_turn
      perform_turn!(turn)

      # An in-process step always finishes its turn and opens the next one or
      # ends the run. If it did neither, something else changed the run under
      # us (a cancel, a second process): stop instead of spinning.
      reload
      break if !run_over? && current_turn.id == turn.id
    end

    final_answer
  rescue Raif::Errors::AgentRunError
    raise
  rescue StandardError => e
    record_run_failure(e)
    raise
  end

  # Starts the run in background jobs and returns immediately.
  #
  # Progress is reported through overridable methods instead of a block, because
  # a block cannot travel between jobs: #after_conversation_history_entry,
  # #after_tool_calls_dispatched, #after_turn, #after_run.
  #
  # @return [Raif::Agent] self
  def run_later!
    start_run!("async")
    enqueue_turn_job(current_turn)
    self
  end

  # Moves a stopped async run forward again. Safe to call at any time and any
  # number of times: it queues the job that the saved state needs, and that job
  # does nothing if the run already moved on. Raif::RecoverStalledRunsJob calls
  # this for runs that stopped changing.
  #
  # @return [Boolean] whether a job was queued
  def resume!
    return false unless persisted? && started? && run_mode == "async"
    return false if reload.run_over?

    turn = current_turn
    return false if turn.nil?

    # Space out repeated recovery attempts for a turn that is waiting legitimately.
    turn.touch
    enqueue_turn_job(turn)
    true
  end

  # Stops the run. Jobs that are queued or running for it do nothing more, and
  # results that arrive later are ignored. Use it to supersede a run.
  #
  # @return [Boolean] false when the run was already over
  def cancel!
    canceled = run_transaction do
      next false if run_over?

      self.canceled_at = Time.current
      self.run_token = SecureRandom.hex(16)
      save!
      raif_model_tool_invocations.unfinished.update_all(canceled_at: canceled_at, updated_at: canceled_at)
      true
    end

    after_run if canceled
    canceled
  end

  # @return [Symbol] :pending, :running, :waiting, :completed, :failed, or :canceled
  def status
    return :canceled if canceled_at?
    return :failed if failed_at?
    return :completed if completed_at?
    return :pending unless started_at?

    waiting? ? :waiting : :running
  end

  # True while the current turn waits for tool calls to end. No model call
  # happens and no iteration is used while the agent waits.
  def waiting?
    return false if !started_at? || run_over?

    current_turn&.tools_dispatched? || false
  end

  # The tool invocations the run is waiting for.
  def pending_tool_invocations
    turn = current_turn
    return Raif::ModelToolInvocation.none unless turn&.tools_dispatched?

    turn.raif_model_tool_invocations.unfinished.in_call_order
  end

  def run_over?
    completed_at? || failed_at? || canceled_at?
  end

  def in_process_run?
    run_mode == "in_process"
  end

  def current_turn
    turns.reorder(iteration: :desc).first&.bind_agent(self)
  end

  # Restores host context around every step of a run: each turn job, each tool
  # job, and the continuation that a deadline or a host `complete!` call starts.
  # Jobs run outside the request that started the run, so per-request state
  # (current-attributes objects, a permission scope) is gone unless this method
  # sets it again. Override it and yield:
  #
  #   def with_run_context
  #     Current.set(account: source.account) { yield }
  #   end
  def with_run_context
    yield
  end

  # Called after each entry is added to the conversation history. The default
  # calls the block given to #run!.
  #
  # This hook and #after_tool_calls_dispatched, #after_turn and #after_run run
  # after the step they report has committed. In a job, an error they raise is
  # reported to Rails.error and the run continues. Under #run! it is raised to
  # the caller and fails the run.
  def after_conversation_history_entry(entry)
    on_conversation_history_entry&.call(entry)
  end

  # Called when a turn's tool calls were created and are about to run. The
  # calls are not in the conversation history yet.
  def after_tool_calls_dispatched(turn)
  end

  # Called when a turn is finished. Can run more than once for a turn if the
  # process stops during the continuation, so keep it idempotent.
  def after_turn(turn)
  end

  # Called when the run is over: completed, failed, or canceled. Can run more
  # than once after a crash, so keep it idempotent.
  def after_run
  end

  # --- Steps. Public because jobs and the barrier call them; not host API. ---

  # Does whatever the turn's saved state still needs. Every branch re-reads the
  # state, so calling this for a turn that already moved on does nothing.
  def perform_turn!(turn)
    turn.bind_agent(self)

    with_run_context do
      request_turn_completion!(turn) if turn.pending?
      process_turn_completion!(turn) if turn.completion_saved?
      run_turn_tool_invocations!(turn) if turn.tools_dispatched?
      continue_after_turn!(turn) if turn.tools_complete?
    end
  end

  # tools_complete -> completed. Opens the next turn, or ends the run, in the
  # same transaction that marks this turn completed, so a crash cannot leave a
  # finished turn with nothing after it.
  def continue_after_turn!(turn)
    next_turn = nil

    continued = run_transaction do
      next false unless turn.reload.tools_complete?

      if run_live?
        if final_answer.present? || iteration_count >= max_iterations
          finalize_run!
        else
          next_turn = open_turn!(iteration_count + 1)
        end
      end

      turn.transition!(from: "tools_complete", to: "completed", completed_at: Time.current)
    end
    return unless continued

    enqueue_turn_job(next_turn) if next_turn.present? && !in_process_run?
    run_host_hook(:after_turn) { after_turn(turn) }
    run_host_hook(:after_run) { after_run } if next_turn.nil? && run_over?
  end

  # Runs the block in a transaction that holds the agent's row lock, on the
  # current state of the row. Every change to the run goes through here: turn
  # jobs, tool jobs and host calls can all touch the same run at once, and the
  # conversation history is a single column that would otherwise lose updates.
  def run_transaction
    if @run_transaction_depth.to_i > 0
      return yield
    end

    # Locking reloads the row, which Rails refuses while attributes are unsaved.
    # A subclass hook may have assigned some, so they are saved first.
    save! if changed?

    @run_transaction_depth = 1
    begin
      result = with_lock { yield }
    rescue StandardError
      # The transaction rolled back, so the entries it added were never saved.
      @conversation_history_callback_queue = []
      raise
    ensure
      @run_transaction_depth = 0
    end

    flush_conversation_history_callbacks
    result
  end

  # Whether this process may still change the run. Call it inside #run_transaction.
  def run_live?
    return false if run_over?

    @held_run_token.nil? || @held_run_token == run_token
  end

  # A job holds the token it was queued with. If the run was canceled or
  # superseded since, the tokens differ and the job changes nothing.
  def hold_run_token(token)
    @held_run_token = token
  end

  def tool_error_recoverable?(error)
    self.class.recover_from_tool_errors && recoverable_tool_error?(error)
  end

  def tool_error_message_for_model(tool_name, error)
    tool_error_result_message(tool_name, error)
  end

  # A tool error the model cannot work around ends the run. Calls that did not
  # start are canceled; a call that is already running finishes, and its result
  # is saved but changes nothing.
  def fail_run_from_tool_error!(invocation, error)
    failed = run_transaction do
      next false if run_over?

      fail_run!(error.message)
      now = Time.current
      raif_model_tool_invocations.unfinished.where(started_at: nil).update_all(canceled_at: now, updated_at: now)
      true
    end
    run_host_hook(:after_run) { after_run } if failed
  end

  # Records the results of a turn's tool calls in the conversation history, in
  # call order. Called by the barrier, inside #run_transaction.
  def record_turn_tool_results!(turn)
    # no-op by default
  end

private

  def ensure_no_deferred_tools!
    deferred = available_model_tools_map.values.select(&:deferred_completion?)
    return if deferred.empty?

    raise Raif::Errors::AgentRunError,
      "#{self.class.name}#run! cannot wait for tools that defer completion (#{deferred.map(&:tool_name).join(", ")}). Use #run_later!."
  end

  # One transaction, so a crash cannot leave a started run without its first
  # turn, which neither #resume! nor the recovery sweep could continue. A refusal
  # rolls it back and leaves no failed run behind.
  def start_run!(mode)
    if persisted? && (started_at? || turns.exists?)
      raise Raif::Errors::AgentRunError, "#{self.class.name}##{id} was already started. Use #resume! to continue an async run."
    end

    transaction do
      # Creating the record runs populate_default_model_tools, so the tool set
      # is complete only after this save.
      save!
      ensure_no_deferred_tools! if mode == "in_process"

      self.started_at = Time.current
      self.run_mode = mode
      self.run_token = SecureRandom.hex(16)
      save!
      hold_run_token(run_token)

      run_transaction do
        add_conversation_history_entry(Raif::Messages::UserMessage.new(content: task).to_h)
        open_turn!(1)
      end
    end

    logger.debug <<~DEBUG
      --------------------------------
      Starting Agent Run
      --------------------------------
      System Prompt:
      #{system_prompt}

      Task: #{task}
    DEBUG
  end

  def open_turn!(iteration)
    update_columns(iteration_count: iteration)
    turns.create!(iteration: iteration)
  end

  def enqueue_turn_job(turn)
    queue = self.class.turn_job_queue || Raif.config.agent_turn_job_queue
    job = queue.present? ? Raif::AgentTurnJob.set(queue: queue) : Raif::AgentTurnJob
    token = run_token
    Raif::ApplicationJob.after_transaction_commit { job.perform_later(agent: self, turn_id: turn.id, run_token: token) }
  end

  # pending -> completion_saved
  def request_turn_completion!(turn)
    prepared = run_transaction do
      next false unless run_live? && turn.reload.pending?

      # The warnings a subclass adds before the model call go into the history
      # once per turn, even if this step runs again.
      if turn.started_at.blank?
        # Update the system prompt on each iteration in case it has changed since the last iteration
        self.system_prompt = build_system_prompt
        before_iteration_llm_chat
        save!
        turn.update!(started_at: Time.current)
      end
      true
    end
    return unless prepared

    # A completion that was saved without reaching the turn (the process stopped
    # in between) is used instead of paying for the model call again.
    model_completion = unattached_model_completion(turn) || request_model_completion

    run_transaction do
      next unless run_live?

      turn.transition!(from: "pending", to: "completion_saved", raif_model_completion_id: model_completion.id)
    end
  end

  def unattached_model_completion(turn)
    completions = Raif::ModelCompletion.arel_table

    raif_model_completions
      .where.not(completed_at: nil)
      .where(failed_at: nil)
      .where(completions[:created_at].gteq(turn.started_at))
      .where.not(id: turns.where.not(raif_model_completion_id: nil).select(:raif_model_completion_id))
      .reorder(:id)
      .last
  end

  def request_model_completion
    messages = messages_for_llm

    model_completion = llm.chat(
      messages: messages,
      source: self,
      system_prompt: system_prompt,
      available_model_tools: native_model_tools,
      tool_choice: tool_choice_for_iteration,
      allow_parallel_tool_calls: allow_parallel_tool_calls?,
      anthropic_prompt_caching_enabled: self.class.anthropic_prompt_caching_enabled,
      bedrock_prompt_caching_enabled: self.class.bedrock_prompt_caching_enabled,
      open_ai_store_responses: self.class.open_ai_store_responses,
      open_router_data_collection: self.class.open_router_data_collection,
      open_router_zdr: self.class.open_router_zdr
    )

    logger.debug <<~DEBUG
      --------------------------------
      Agent iteration #{iteration_count}
      Messages:
      #{JSON.pretty_generate(messages)}

      Response:
      #{model_completion.raw_response}
      --------------------------------
    DEBUG

    model_completion
  end

  # completion_saved -> tools_dispatched or tools_complete.
  #
  # The default serves agent classes that implement
  # #process_iteration_model_completion: the whole completion is processed in
  # this step and no tool jobs are dispatched. The hook runs outside the agent's
  # lock, because the tools it runs would otherwise hold the lock for as long as
  # they take and block every other writer of the run. If the process stops
  # before the turn moves on, the hook runs again.
  def process_turn_completion!(turn)
    return unless run_transaction { run_live? && turn.reload.completion_saved? }

    process_iteration_model_completion(turn.raif_model_completion)

    run_transaction do
      next unless run_live?

      turn.transition!(from: "completion_saved", to: "tools_complete", tools_completed_at: Time.current)
    end
  end

  # tools_dispatched: start every tool call that has not started, then check the
  # barrier. Also the recovery path for a turn whose tool jobs were never queued.
  def run_turn_tool_invocations!(turn)
    invocations = turn.raif_model_tool_invocations.in_call_order.to_a
    startable = invocations.reject(&:finished?).select { |invocation| invocation.started_at.blank? || invocation.tool.retry_safe? }

    # One call gains nothing from a job of its own, so it runs right here.
    if in_process_run? || invocations.one?
      startable.each do |invocation|
        invocation.barrier_owner = turn
        invocation.execute!(context_established: true, raise_fatal: in_process_run?)
      end
    else
      startable.each { |invocation| enqueue_tool_invocation_job(invocation) }
    end

    turn.check_tool_barrier!
  end

  def enqueue_tool_invocation_job(invocation)
    queue = self.class.tool_invocation_job_queue || Raif.config.model_tool_invocation_job_queue
    job = queue.present? ? Raif::ModelToolInvocationJob.set(queue: queue) : Raif::ModelToolInvocationJob
    Raif::ApplicationJob.after_transaction_commit { job.perform_later(model_tool_invocation: invocation) }
  end

  def record_run_failure(error)
    reload if persisted?
    return if failed_at? && failure_reason.present?

    self.failed_at ||= Time.current
    self.failure_reason ||= error.message
    save!
    after_run
  end

  def flush_conversation_history_callbacks
    entries = @conversation_history_callback_queue
    return if entries.blank?

    @conversation_history_callback_queue = []
    entries.each { |entry| run_host_hook(:after_conversation_history_entry) { after_conversation_history_entry(entry) } }
  end

  # A step whose hook raises has already committed. In a job, failing the run
  # for it would end a run that is healthy, so the error is reported instead.
  def run_host_hook(name)
    yield
  rescue StandardError => e
    raise if in_process_run?

    Rails.error.report(e, handled: true, severity: :error, context: { component: "raif_agent", action: name.to_s, agent_id: id })
    nil
  end
end
