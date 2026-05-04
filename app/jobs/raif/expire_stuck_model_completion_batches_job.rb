# frozen_string_literal: true

module Raif
  # Hourly safety sweep for Raif::ModelCompletionBatch records whose polling
  # chain went stale -- e.g. a scheduled job got dropped during a queue
  # backend restart, or a long-running batch outlived our tolerance.
  #
  # For each non-terminal batch with submitted_at older than
  # Raif.config.model_completion_batch_max_age, marks the batch as `failed`
  # and dispatches the configured completion handler so any waiting workflow
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
          batch.force_fail!(reason: "Batch exceeded Raif.config.model_completion_batch_max_age (#{max_age})")
          batch.dispatch_completion_handler!
        end
    end

  end
end
