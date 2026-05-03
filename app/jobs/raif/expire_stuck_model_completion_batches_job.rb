# frozen_string_literal: true

module Raif
  # Hourly safety sweep for Raif::ModelCompletionBatch records whose polling
  # chain went stale -- e.g. a Sidekiq scheduled-set entry got dropped during a
  # Redis flush or a long-running batch outlived our tolerance.
  #
  # For each non-terminal batch with submitted_at older than
  # Raif.config.model_completion_batch_max_age, marks the batch as `failed`
  # and dispatches the configured completion handler so any waiting workflow
  # step can advance.
  #
  # Should be scheduled hourly by the host app (e.g. via sidekiq-cron).
  class ExpireStuckModelCompletionBatchesJob < ApplicationJob

    def perform
      max_age = Raif.config.model_completion_batch_max_age
      cutoff = max_age.ago

      Raif::ModelCompletionBatch
        .non_terminal
        .where(arel_table_for_batch[:submitted_at].not_eq(nil))
        .where(arel_table_for_batch[:submitted_at].lt(cutoff))
        .find_each do |batch|
          force_fail!(batch, reason: "Batch exceeded Raif.config.model_completion_batch_max_age (#{max_age})")
          batch.dispatch_completion_handler!
        end
    end

  private

    def arel_table_for_batch
      Raif::ModelCompletionBatch.arel_table
    end

    def force_fail!(batch, reason:)
      batch.raif_model_completions.each do |mc|
        next if mc.reload.completed? || mc.failed?

        mc.failure_error = "Raif::ModelCompletionBatch ##{batch.id} expired"
        mc.failure_reason = reason.to_s.truncate(255)
        mc.update_columns(started_at: batch.started_at) if mc.started_at.nil?
        mc.failed!
      end

      batch.update!(status: "failed", failed_at: Time.current, failure_reason: reason.to_s.truncate(255))
    end

  end
end
