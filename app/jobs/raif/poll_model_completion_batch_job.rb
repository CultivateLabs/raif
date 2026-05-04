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
  # The self-reschedule uses `perform_later(wait: ...)`, so the configured
  # ActiveJob queue adapter must support scheduled jobs. If the host app's
  # queue adapter exposes a job-grouping primitive that auto-enrolls jobs
  # enqueued from within a running job, the polling chain will participate
  # in that grouping transparently.
  class PollModelCompletionBatchJob < ApplicationJob

    def perform(batch_id, attempt: 1)
      batch = Raif::ModelCompletionBatch.find_by(id: batch_id)
      return if batch.nil? || batch.terminal?

      batch.fetch_status!

      if batch.terminal?
        batch.finalize!
        batch.dispatch_completion_handler!
        return
      end

      if batch.max_age_exceeded?
        batch.force_fail!(reason: "Batch exceeded Raif.config.model_completion_batch_max_age (#{Raif.config.model_completion_batch_max_age})")
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

    def next_poll_delay(attempt)
      schedule = Array(Raif.config.model_completion_batch_poll_schedule)
      return 1.minute if schedule.empty?

      idx = (attempt - 1).clamp(0, schedule.size - 1)
      schedule[idx]
    end

  end
end
