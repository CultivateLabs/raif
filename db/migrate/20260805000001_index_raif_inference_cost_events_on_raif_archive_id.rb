# frozen_string_literal: true

# Index-only migration, split from CreateRaifArchives: the events table is
# large in host apps, so on PostgreSQL the index must build without blocking
# writes, which requires disabling the DDL transaction. Isolating the
# non-transactional step means a failed index build can simply be retried;
# the transactional schema additions in the previous migration are already
# safely recorded.
class IndexRaifInferenceCostEventsOnRaifArchiveId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    if connection.adapter_name.downcase.include?("postg")
      add_index :raif_inference_cost_events, :raif_archive_id, algorithm: :concurrently
    else
      add_index :raif_inference_cost_events, :raif_archive_id
    end
  end
end
