# frozen_string_literal: true

module Raif
  module Errors
    # Raised by Raif::InferenceCostEvent.backfill! when one or more terminal
    # model completions could not be synced. Lets callers (the rake task, and
    # Raif::RepairInferenceCostEventsJob via retry_on) see a partial failure
    # instead of the run reporting success with events still missing.
    class InferenceCostEventsBackfillError < StandardError
    end
  end
end
