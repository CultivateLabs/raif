# frozen_string_literal: true

module Raif
  # Self-healing for inference cost events: creates events for terminal
  # Raif::ModelCompletion records that are missing one. Enqueued whenever a
  # live sync fails (see Raif::ModelCompletion#sync_inference_cost_event,
  # which never fails the completion save); hosts may also schedule it
  # periodically as a safety net.
  #
  # Idempotent: runs the same scope and sync path as
  # Raif::InferenceCostEvent.backfill!, so concurrent or repeated runs
  # converge on one event per terminal completion.
  class RepairInferenceCostEventsJob < ApplicationJob

    def perform(batch_size: 500)
      Raif::InferenceCostEvent.backfill!(batch_size: batch_size)
    end

  end
end
