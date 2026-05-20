# frozen_string_literal: true

module Raif
  # Recovery sweep for Raif::ModelCompletionBatch records whose self-rescheduling
  # poll chain (Raif::PollModelCompletionBatchJob) was dropped -- e.g. a
  # scheduled job evicted on a queue backend restart, an ActiveJob retry
  # ceiling reached, or a deploy that drained the queue before the next poll
  # fired. Without recovery, such batches sit non-terminal until the
  # hourly Raif::ExpireStuckModelCompletionBatchesJob force-fails them at
  # max_age, discarding any results the provider may have produced in the
  # meantime.
  #
  # For each non-terminal batch whose next_poll_at is in the past by at least
  # POLL_GRACE, this sweep enqueues a fresh Raif::PollModelCompletionBatchJob.
  # That job is idempotent at the top (terminal? check + handler-dispatched
  # gating), and batch.fetch_status! is a read against the provider, so a
  # concurrent normally-firing poll plus this sweep at most causes a duplicate
  # provider status request.
  #
  # Pairs with Raif::ExpireStuckModelCompletionBatchesJob to form a
  # recover-then-expire pattern: host apps should schedule this sweep
  # frequently (every ~5 minutes) and the expire sweep hourly. The resume
  # sweep tries to reclaim results before the expire sweep declares the
  # batch lost.
  class ResumeStalledModelCompletionBatchPollsJob < ApplicationJob

    # Skip batches whose next_poll_at landed within this window. A poll job
    # that fires at exactly next_poll_at takes a moment to call reschedule!,
    # so a too-small grace would race the normally-firing chain. 5 minutes
    # is comfortably outside the tightest entry in the default poll schedule
    # (60s) without leaving stranded batches unattended for long.
    POLL_GRACE = 5.minutes

    def perform
      cutoff = POLL_GRACE.ago

      Raif::ModelCompletionBatch
        .due_for_poll(at: cutoff)
        .find_each do |batch|
          Raif::PollModelCompletionBatchJob.perform_later(batch.id)
          Raif.logger.info(
            "Raif::ResumeStalledModelCompletionBatchPollsJob: enqueued poll for batch ##{batch.id} " \
              "(status=#{batch.status}, next_poll_at=#{batch.next_poll_at&.iso8601 || "nil"}, " \
              "provider_batch_id=#{batch.provider_batch_id.inspect})"
          )
        rescue StandardError => e
          # Per-batch rescue so a single bad enqueue (queue-backend hiccup,
          # serialization failure) doesn't block recovery of every later batch
          # in the sweep. The next tick re-enters and retries any batch that's
          # still due_for_poll.
          Raif.logger.error(
            "Raif::ResumeStalledModelCompletionBatchPollsJob: failed to enqueue poll for batch ##{batch.id}: #{e.class}: #{e.message}"
          )
          Raif.logger.error(e.backtrace.first(20).join("\n")) if e.backtrace.present?

          if defined?(Airbrake)
            notice = Airbrake.build_notice(e)
            notice[:context][:component] = "raif_resume_stalled_model_completion_batch_polls_job"
            notice[:params] = { batch_id: batch.id }
            Airbrake.notify(notice)
          end
        end
    end

  end
end
