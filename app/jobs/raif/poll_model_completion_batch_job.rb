# frozen_string_literal: true

module Raif
  # Self-rescheduling poller for Raif::ModelCompletionBatch.
  #
  # Each invocation:
  # 1. Loads the batch. Returns immediately if already terminal (idempotent).
  # 2. Asks the LLM provider for the batch's current status.
  # 3. If terminal:
  #    - on `ended`: fetches per-entry results via the LLM, which marks each
  #      child Raif::ModelCompletion as completed or failed.
  #    - on `failed` / `canceled` / `expired`: marks every child completion
  #      that's still pending as failed with the batch's terminal status as
  #      the reason; no per-entry fetch happens.
  #    Then dispatches the batch's completion handler (if any).
  # 4. Otherwise re-enqueues itself with the next backoff delay from
  #    Raif.config.model_completion_batch_poll_schedule (the last entry
  #    repeats once exhausted) until Raif.config.model_completion_batch_max_age
  #    has elapsed since the batch was submitted, after which the batch is
  #    force-failed and the handler is dispatched.
  #
  # When this job runs inside a Sidekiq batch (e.g. spawned by a workflow
  # step), the chained `perform_later(wait: ...)` self-reschedule is
  # auto-enrolled in the same Sidekiq batch, which keeps the batch open
  # across the polling chain so downstream workflow steps wait for completion.
  class PollModelCompletionBatchJob < ApplicationJob

    def perform(batch_id, attempt: 1)
      batch = Raif::ModelCompletionBatch.find_by(id: batch_id)
      return if batch.nil? || batch.terminal?

      new_status = batch.fetch_status!

      if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(new_status)
        handle_terminal_batch!(batch)
        batch.dispatch_completion_handler!
        return
      end

      if max_age_exceeded?(batch)
        force_fail!(batch, reason: "Batch exceeded Raif.config.model_completion_batch_max_age (#{Raif.config.model_completion_batch_max_age})")
        batch.dispatch_completion_handler!
        return
      end

      delay = next_poll_delay(attempt)
      batch.update_column(:next_poll_at, delay.from_now)
      self.class.set(wait: delay).perform_later(batch_id, attempt: attempt + 1)
    rescue StandardError => e
      Raif.logger.error("Raif::PollModelCompletionBatchJob ##{batch_id} failed: #{e.class}: #{e.message}")
      Raif.logger.error(e.backtrace.first(20).join("\n")) if e.backtrace.present?

      if defined?(Airbrake)
        notice = Airbrake.build_notice(e)
        notice[:context][:component] = "raif_poll_model_completion_batch_job"
        notice[:params] = { batch_id: batch_id }
        Airbrake.notify(notice)
      end

      raise
    end

  private

    # On `ended`, fetch per-entry results from the provider; on the other
    # terminal statuses there are no results to fetch, so we mark every
    # still-pending child completion as failed with the batch's terminal
    # status as the failure reason.
    def handle_terminal_batch!(batch)
      if batch.successful?
        batch.fetch_results!
      else
        force_fail!(batch, reason: "Batch ended with status: #{batch.status}")
      end
    end

    def force_fail!(batch, reason:)
      batch.raif_model_completions.each do |mc|
        next unless mc.reload.pending? || mc.started_at.present? && mc.completed_at.blank? && mc.failed_at.blank?

        mc.failure_error = "Raif::ModelCompletionBatch ##{batch.id} #{batch.status}"
        mc.failure_reason = reason.to_s.truncate(255)
        mc.update_columns(started_at: batch.started_at) if mc.started_at.nil?
        mc.failed!
      end

      unless batch.terminal?
        batch.update!(status: "failed", failed_at: Time.current, failure_reason: reason.to_s.truncate(255))
      end
    end

    def max_age_exceeded?(batch)
      submitted = batch.submitted_at
      return false if submitted.blank?

      max_age = Raif.config.model_completion_batch_max_age
      Time.current - submitted >= max_age
    end

    def next_poll_delay(attempt)
      schedule = Array(Raif.config.model_completion_batch_poll_schedule)
      return 1.minute if schedule.empty?

      idx = (attempt - 1).clamp(0, schedule.size - 1)
      schedule[idx]
    end

  end
end
