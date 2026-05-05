# frozen_string_literal: true

module Raif
  # Hourly safety sweep for Raif::ModelCompletionBatch records whose polling
  # chain went stale -- e.g. a scheduled job got dropped during a queue
  # backend restart, or a long-running batch outlived our tolerance.
  #
  # For each non-terminal batch with submitted_at older than
  # Raif.config.model_completion_batch_max_age, calls #expire! (which issues a
  # best-effort provider-side cancel before marking the batch failed locally),
  # then dispatches the configured completion handler so any waiting workflow
  # step can advance.
  #
  # Should be scheduled hourly by the host app via whichever cron / recurring
  # job mechanism the host's queue adapter uses.
  class ExpireStuckModelCompletionBatchesJob < ApplicationJob

    def perform
      max_age = Raif.config.model_completion_batch_max_age
      cutoff = max_age.ago
      batches_table = Raif::ModelCompletionBatch.arel_table

      Raif::ModelCompletionBatch
        .non_terminal
        .where(batches_table[:submitted_at].not_eq(nil))
        .where(batches_table[:submitted_at].lt(cutoff))
        .find_each do |batch|
          batch.expire!(reason: "Batch exceeded Raif.config.model_completion_batch_max_age (#{max_age})")
          batch.dispatch_completion_handler!
        rescue StandardError => e
          # Per-batch rescue so a single bad handler (or a transient DB hiccup
          # mid-force_fail!) doesn't block expiry of every later batch in the
          # sweep. The next hourly tick re-enters and retries any batch that's
          # still non-terminal; a batch that expired locally but whose handler
          # raised will be picked up by the polling job's handler-retry path
          # via handler_dispatched_at gating.
          Raif.logger.error(
            "Raif::ExpireStuckModelCompletionBatchesJob: failed to expire batch ##{batch.id}: #{e.class}: #{e.message}"
          )
          Raif.logger.error(e.backtrace.first(20).join("\n")) if e.backtrace.present?

          if defined?(Airbrake)
            notice = Airbrake.build_notice(e)
            notice[:context][:component] = "raif_expire_stuck_model_completion_batches_job"
            notice[:params] = { batch_id: batch.id }
            Airbrake.notify(notice)
          end
        end
    end

  end
end
