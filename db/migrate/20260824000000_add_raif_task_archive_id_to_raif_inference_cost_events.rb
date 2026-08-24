# frozen_string_literal: true

# Transactional column addition only. Its index is concurrent and lives in
# the next migration, for the reason CreateRaifArchives documents.
class AddRaifTaskArchiveIdToRaifInferenceCostEvents < ActiveRecord::Migration[7.1]
  def change
    # The task-side twin of raif_archive_id, which stamps the archive holding
    # the event's model completion. Different jobs archive a task and its
    # completion into different objects, so one column cannot serve both.
    # Plain bigint, no FK, for the reasons CreateRaifArchives gives.
    add_column :raif_inference_cost_events, :raif_task_archive_id, :bigint
  end
end
