# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completion_batches
#
#  id                            :bigint           not null, primary key
#  completion_handler_class_name :string
#  creator_type                  :string
#  ended_at                      :datetime
#  failed_at                     :datetime
#  failure_error                 :string
#  failure_reason                :text
#  handler_dispatched_at         :datetime
#  llm_model_key                 :string           not null
#  metadata                      :jsonb
#  model_api_name                :string           not null
#  next_poll_at                  :datetime
#  output_token_cost             :decimal(10, 6)
#  prompt_token_cost             :decimal(10, 6)
#  provider_response             :jsonb
#  request_counts                :jsonb
#  results_fetched_at            :datetime
#  started_at                    :datetime
#  status                        :string           default("pending"), not null
#  submitted_at                  :datetime
#  total_cost                    :decimal(10, 6)
#  type                          :string           not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  creator_id                    :bigint
#  provider_batch_id             :string
#
# Indexes
#
#  index_raif_model_completion_batches_on_creator            (creator_type,creator_id)
#  index_raif_model_completion_batches_on_next_poll_at       (next_poll_at)
#  index_raif_model_completion_batches_on_provider_batch_id  (provider_batch_id)
#  index_raif_model_completion_batches_on_status             (status)
#  index_raif_model_completion_batches_on_submitted_at       (submitted_at)
#  index_raif_model_completion_batches_on_type               (type)
#
module Raif
  class ModelCompletionBatch < Raif::ApplicationRecord
    STATUSES = %w[pending submitted in_progress ended canceled expired failed].freeze
    TERMINAL_STATUSES = %w[ended canceled expired failed].freeze

    belongs_to :creator, polymorphic: true, optional: true

    has_many :raif_model_completions,
      class_name: "Raif::ModelCompletion",
      foreign_key: :raif_model_completion_batch_id,
      inverse_of: :raif_model_completion_batch,
      dependent: :nullify

    validates :type, presence: true
    validates :llm_model_key, presence: true
    validates :model_api_name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    after_initialize -> { self.metadata ||= {} }
    after_initialize -> { self.provider_response ||= {} }
    after_initialize -> { self.request_counts ||= {} }

    scope :pending, -> { where(status: "pending") }
    scope :submitted, -> { where(status: "submitted") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :ended, -> { where(status: "ended") }
    scope :failed, -> { where(status: "failed") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :non_terminal, -> { where.not(status: TERMINAL_STATUSES) }
    scope :due_for_poll, ->(at: Time.current) { non_terminal.where(arel_table[:next_poll_at].lteq(at)) }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def successful?
      status == "ended"
    end

    def llm
      Raif.llm(llm_model_key.to_sym)
    end

    # Convenience accessor for batches whose children were produced via
    # Raif::Task.build_for_batch (the typical case). Returns the Raif::Task
    # records attached to this batch through their child Raif::ModelCompletions.
    #
    # Heterogeneous batches that mix Raif::Task producers with raw
    # Raif::Llm#build_pending_model_completion producers will see only the
    # Raif::Task subset here; use raif_model_completions for full coverage.
    def tasks
      Raif::Task.where(
        id: raif_model_completions.where(source_type: "Raif::Task").select(:source_id)
      )
    end

    # Attaches an existing Raif::Task to this batch as a pending child
    # completion. The task is persisted if not already, then routed through
    # Raif::Task#prepare_for_batch! to populate prompts and build the pending
    # Raif::ModelCompletion.
    #
    # Pair with Raif::Llm#create_batch when the producer constructs tasks
    # outside of the batch (composing them in a loop, in a service object,
    # etc.). For the one-call shortcut – build + save + attach in a single
    # call – use Raif::Task.build_for_batch instead.
    #
    # @param task [Raif::Task]
    # @param batch_custom_id [String, nil] unique-within-batch identifier;
    #   defaults to "raif_task_<task.id>".
    # @return [Raif::Task] the same task, now attached to this batch.
    def add_task(task, batch_custom_id: nil)
      task.save! if task.new_record?
      task.prepare_for_batch!(batch: self, batch_custom_id: batch_custom_id)
      task
    end

    # Consumer-facing API: ask the batch to do its provider's work.
    #
    # Each method delegates to the LLM provider's SupportsBatchInference
    # implementation. The provider-side methods (Raif::Llm#submit_batch!,
    # #fetch_batch_status!, #fetch_batch_results!, #cancel_batch!) are the
    # contract every batch-capable provider implements; these façades are
    # how callers actually invoke them.

    # Submits the batch to the provider and (by default) enqueues
    # Raif::PollModelCompletionBatchJob so the polling chain starts on its
    # own. Pass enqueue_poll: false if your host app is driving its own
    # poll scheduler off the Raif::ModelCompletionBatch.due_for_poll scope.
    #
    # @param enqueue_poll [Boolean] whether to auto-enqueue the polling job
    # @return [Raif::ModelCompletionBatch] self
    def submit!(enqueue_poll: true)
      result = llm.submit_batch!(self)
      enqueue_first_poll! if enqueue_poll
      result
    end

    # Stamps next_poll_at and enqueues the first Raif::PollModelCompletionBatchJob
    # using the first entry of Raif.config.model_completion_batch_poll_schedule.
    # Called by #submit! by default; can also be invoked manually if a host
    # opted out of auto-enqueue (#submit!(enqueue_poll: false)) and wants to
    # start polling later.
    #
    # Guards against being called on a batch that hasn't been submitted yet
    # (no provider_batch_id, so the polling job's fetch_batch_status! would
    # 404 and burn the entire poll schedule until max_age expiry) or that's
    # already terminal (nothing to poll for). Raises Raif::Errors::InvalidBatchError
    # so a misordered call surfaces immediately instead of silently scheduling
    # a doomed poll chain.
    def enqueue_first_poll!
      if provider_batch_id.blank?
        raise Raif::Errors::InvalidBatchError,
          "Raif::ModelCompletionBatch ##{id}#enqueue_first_poll! requires provider_batch_id; " \
            "call submit! (or llm.submit_batch!(batch)) first."
      end
      if terminal?
        raise Raif::Errors::InvalidBatchError,
          "Raif::ModelCompletionBatch ##{id}#enqueue_first_poll! refusing to schedule a poll " \
            "for a terminal batch (status=#{status})."
      end

      delay = Array(Raif.config.model_completion_batch_poll_schedule).first || 1.minute
      update_column(:next_poll_at, delay.from_now)
      Raif::PollModelCompletionBatchJob.set(wait: delay).perform_later(id)
    end

    def fetch_status!
      llm.fetch_batch_status!(self)
    end

    def fetch_results!
      llm.fetch_batch_results!(self)
    end

    # Asks the provider to cancel the batch. Cancellation is asynchronous on
    # both Anthropic and OpenAI: the provider acknowledges with a transitional
    # status and the next poll picks up the final canceled state. The polling
    # job then routes the canceled batch through the same finalize/dispatch
    # path as any other terminal status, force-failing remaining children.
    def cancel!
      llm.cancel_batch!(self)
    end

    # Idempotency guard for batch submission. Raises Raif::Errors::InvalidBatchError
    # if the batch already has a provider_batch_id or has moved past `pending`,
    # so a duplicate batch.submit! / llm.submit_batch!(batch) call cannot create
    # a second provider-side batch and orphan the first one. Called by every
    # provider's #submit_batch! at the top of the method.
    def assert_submittable!
      return if status == "pending" && provider_batch_id.blank?

      raise Raif::Errors::InvalidBatchError,
        "Raif::ModelCompletionBatch ##{id} is not submittable: status=#{status}, " \
          "provider_batch_id=#{provider_batch_id.inspect}. submit! / submit_batch! " \
          "is single-shot; use #cancel! and create a new batch if you need to retry."
    end

    # Resolves and invokes the batch's completion handler, if one is configured.
    # The handler class must implement `.handle_batch_completion(batch)`.
    #
    # Idempotent via handler_dispatched_at: once a successful run finishes, future
    # callers (the polling job's terminal-batch path, the safety sweep, an
    # ActiveJob retry of either) skip the dispatch. If the handler raises,
    # handler_dispatched_at stays NULL so a future caller can re-dispatch --
    # without that retry path the polling job's `return if batch.terminal?`
    # guard would silently swallow handler-raised errors and the consumer's
    # on_batch_completion block would never run.
    #
    # At-most-once across concurrent callers: the guard + handler invocation +
    # timestamp write are wrapped in #with_lock so a normal poll job racing
    # with the safety sweep (or a resume-stalled poll) cannot both pass the
    # blank-handler_dispatched_at check and run the handler twice. Cheap
    # callers still short-circuit before taking the lock.
    def dispatch_completion_handler!
      return if handler_dispatched_at.present?
      return if completion_handler_class_name.blank?
      # Local-side resolution must be complete before the handler runs --
      # otherwise the handler would dispatch against child completions that
      # haven't been hydrated with their provider results yet, which is how
      # batches got silently stranded under the prior code path.
      return if results_fetched_at.blank?

      handler = completion_handler_class_name.safe_constantize
      if handler.blank?
        Raif.logger.error(
          "Raif::ModelCompletionBatch##{id} has completion_handler_class_name=#{completion_handler_class_name.inspect} " \
            "which could not be resolved to a class. Skipping handler dispatch."
        )
        return
      end

      with_lock do
        # Re-check under lock: another worker may have dispatched between our
        # early-return check above and lock acquisition.
        return if handler_dispatched_at.present?

        handler.handle_batch_completion(self)
        update_column(:handler_dispatched_at, Time.current)
      end
    end

    # True once submitted_at is older than Raif.config.model_completion_batch_max_age.
    # Used by the polling and expire-stuck jobs to decide when to force-fail a batch
    # that the provider hasn't finalized in time.
    def max_age_exceeded?
      return false if submitted_at.blank?

      Time.current - submitted_at >= Raif.config.model_completion_batch_max_age
    end

    # Called by the polling job once the batch reaches a terminal status. On
    # `ended` (successful), fetches per-entry results from the provider. On the
    # other terminal statuses (canceled / expired / failed), force-fails every
    # still-pending child completion since there are no per-entry results to
    # collect.
    #
    # Idempotent via results_fetched_at: once a successful run finishes, future
    # callers (the poll job's terminal-at-top path, the safety sweep, an
    # ActiveJob retry of either) skip the provider round-trip. If
    # fetch_results! raises mid-stream, results_fetched_at stays NULL so a
    # subsequent finalize! call retries the fetch -- this is how the
    # poll chain self-heals from transient provider errors on the results
    # endpoint without permanently stranding the child completions.
    #
    # At-most-once across concurrent callers: the guard + fetch + stamp are
    # wrapped in #with_lock so a normal poll job racing with the safety
    # sweep (or a resume-stalled poll) cannot both pass the blank-
    # results_fetched_at check and double-call fetch_results!. Cheap callers
    # still short-circuit before taking the lock.
    def finalize!
      return if results_fetched_at.present?

      with_lock do
        # Re-check under lock: another worker may have hydrated results
        # between our early-return check above and lock acquisition.
        return if results_fetched_at.present?

        if successful?
          fetch_results!
          update_column(:results_fetched_at, Time.current)
        else
          # force_fail! sets results_fetched_at inside its transaction so the
          # success/failure paths converge on the same on-disk signal.
          force_fail!(reason: "Batch ended with status: #{status}")
        end
      end
    end

    # Used by the expiry paths (the polling job's max_age_exceeded? branch and
    # Raif::ExpireStuckModelCompletionBatchesJob) when *we* decide to give up
    # on a batch the provider hasn't finalized yet. Distinct from
    # #force_fail!, which only flips local state -- this method also issues a
    # best-effort provider-side cancel so we don't keep paying for batch
    # results we've stopped reading and don't keep occupying the provider's
    # per-org concurrent-batch quota.
    #
    # Cancellation is best-effort: if it fails (5xx, network, auth, etc.) we
    # log and continue, because the local force-fail still has to happen so
    # any waiting workflow can advance. A still-running provider-side batch
    # will eventually self-finalize via the provider's own timer; the worst
    # case is paying for results we discard.
    #
    # Skips the cancel call entirely when the batch is already terminal (the
    # provider's done with it) or hasn't been submitted yet (no
    # provider_batch_id to cancel).
    def expire!(reason:)
      if !terminal? && provider_batch_id.present?
        begin
          llm.cancel_batch!(self)
        rescue StandardError => e
          Raif.logger.warn(
            "Raif::ModelCompletionBatch ##{id} best-effort provider-side cancel failed " \
              "while expiring: #{e.class}: #{e.message}. Continuing with local force-fail; " \
              "the provider-side batch may still complete and be billed."
          )
        end
      end

      force_fail!(reason: reason)
    end

    # Marks every non-terminal child completion as failed and sets the batch to
    # `failed` (preserving an already-terminal status, e.g. `canceled`). Idempotent:
    # children already completed or failed are skipped.
    #
    # Wrapped in a transaction so a partial failure mid-iteration rolls back the
    # batch-status update too. Without this, an exception while flipping
    # children would leave the batch terminal and prevent the polling/expire
    # jobs from re-entering this path on a future run.
    #
    # Local-only: does not touch the provider. Use #expire! when expiring a
    # batch the provider hasn't finalized yet, so the provider-side batch is
    # canceled on a best-effort basis.
    def force_fail!(reason:)
      reason_str = reason.to_s.truncate(255)

      transaction do
        unless terminal?
          update!(status: "failed", failed_at: Time.current, failure_reason: reason_str)
        end

        raif_model_completions.each do |mc|
          mc.reload
          next if mc.completed? || mc.failed?

          mc.failure_error = "Raif::ModelCompletionBatch ##{id} #{status}"
          mc.failure_reason = reason_str
          mc.update_columns(started_at: started_at) if mc.started_at.nil? && started_at.present?
          mc.failed!
        end

        update_column(:results_fetched_at, Time.current) if results_fetched_at.blank?
      end
    end

    # Aggregates total_cost / prompt_token_cost / output_token_cost from child completions
    # after results have been applied. Should be called by the polling job once
    # all children have been finalized.
    def recalculate_costs!
      if raif_model_completions.empty?
        Raif.logger.warn(
          "Raif::ModelCompletionBatch ##{id}#recalculate_costs! skipped: no child raif_model_completions to aggregate"
        )
        return
      end

      # Three .sum calls instead of one Arel-flavored pick. The dataset is bounded
      # by batch size and these only run once per batch finalization, so the extra
      # round-trips are immaterial and the call is much easier to read.
      prompt_sum = raif_model_completions.sum(:prompt_token_cost)
      output_sum = raif_model_completions.sum(:output_token_cost)
      total_sum = raif_model_completions.sum(:total_cost)

      # ActiveRecord's .sum returns 0 (not nil) when every row's column is NULL.
      # Skip the write if everything is zero so we don't null-out manually-set
      # batch-level cost values from the host (rare, but cheap to guard).
      if prompt_sum.zero? && output_sum.zero? && total_sum.zero?
        Raif.logger.warn(
          "Raif::ModelCompletionBatch ##{id}#recalculate_costs! skipped: every child completion's " \
            "prompt_token_cost / output_token_cost / total_cost is NULL or zero"
        )
        return
      end

      update_columns(
        prompt_token_cost: prompt_sum,
        output_token_cost: output_sum,
        total_cost: total_sum,
        updated_at: Time.current
      )
    end
  end
end
