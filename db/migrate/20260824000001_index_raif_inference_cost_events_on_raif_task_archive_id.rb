# frozen_string_literal: true

# Index-only migration, split from the column addition so a failed
# concurrent build is retryable. See
# IndexRaifInferenceCostEventsOnRaifArchiveId.
class IndexRaifInferenceCostEventsOnRaifTaskArchiveId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    if connection.adapter_name.downcase.include?("postg")
      add_index :raif_inference_cost_events, :raif_task_archive_id, algorithm: :concurrently
    else
      add_index :raif_inference_cost_events, :raif_task_archive_id
    end
  end
end
