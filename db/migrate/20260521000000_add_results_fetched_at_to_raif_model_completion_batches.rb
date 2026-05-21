# frozen_string_literal: true

class AddResultsFetchedAtToRaifModelCompletionBatches < ActiveRecord::Migration[7.1]
  def up
    add_column :raif_model_completion_batches, :results_fetched_at, :datetime

    # Backfill so the new finalize! idempotency guard doesn't cause already-completed
    # historical batches to re-call fetch_batch_results! the next time their poll job
    # fires. We mark a batch as "results fetched" iff its handler was already
    # dispatched AND every child completion is terminal -- which is the on-disk
    # signature of a finalize! that ran successfully under the prior code path.
    #
    # Batches with a dispatched handler but some still-unresolved child completions
    # (the silent-stranding signature this fix targets) are intentionally left with
    # results_fetched_at NULL, so the next poll's terminal-at-top branch can re-run
    # fetch_batch_results! and recover them.
    execute(<<~SQL)
      UPDATE raif_model_completion_batches b
      SET results_fetched_at = COALESCE(b.handler_dispatched_at, b.ended_at, b.failed_at)
      WHERE b.status IN ('ended', 'canceled', 'expired', 'failed')
        AND b.handler_dispatched_at IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM raif_model_completions c
          WHERE c.raif_model_completion_batch_id = b.id
            AND c.completed_at IS NULL
            AND c.failed_at IS NULL
        );
    SQL
  end

  def down
    remove_column :raif_model_completion_batches, :results_fetched_at
  end
end
