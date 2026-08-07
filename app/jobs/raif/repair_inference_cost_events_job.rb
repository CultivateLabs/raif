# frozen_string_literal: true

module Raif
  # Self-healing for inference cost events: creates events for terminal
  # Raif::ModelCompletion records that are missing one and re-syncs events
  # that are stale (older than their completion). Enqueued whenever a live
  # sync fails (see Raif::ModelCompletion#sync_inference_cost_event, which
  # never fails the completion save); hosts should also schedule it
  # periodically, especially with archiving enabled - the archive job never
  # culls a terminal completion whose event is missing or stale, so this job
  # is what makes those rows eligible again.
  #
  # Idempotent: runs the same scope and sync path as
  # Raif::InferenceCostEvent.backfill!, so concurrent or repeated runs
  # converge on one fresh event per terminal completion.
  class RepairInferenceCostEventsJob < ApplicationJob
    # backfill! raises when any record fails to sync, so transient failures
    # get bounded backoff retries from the queue backend instead of the job
    # reporting success with events still missing. Once attempts are
    # exhausted the error surfaces to the backend's dead set/error handling;
    # the next live sync failure or host-scheduled run picks up from there
    # (records with a fresh event are skipped by the missing-or-stale scope).
    retry_on Raif::Errors::InferenceCostEventsBackfillError, wait: :polynomially_longer, attempts: 5

    def perform(batch_size: 500)
      Raif::InferenceCostEvent.backfill!(batch_size: batch_size)
    end

  end
end
