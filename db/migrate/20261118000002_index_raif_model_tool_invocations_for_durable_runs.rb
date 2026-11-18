# frozen_string_literal: true

# Index-only migration, split from AddDurableRunColumns so the indexes can
# build without blocking writes on PostgreSQL. A failed build can be retried.
class IndexRaifModelToolInvocationsForDurableRuns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    options = connection.adapter_name.downcase.include?("postg") ? { algorithm: :concurrently } : {}

    add_index :raif_model_tool_invocations, :raif_agent_turn_id, **options
    # Deadline sweep: unfinished invocations whose deadline passed.
    add_index :raif_model_tool_invocations, :deadline_at, **options
    # Recovery sweep: entries that dispatched tool calls and are not yet terminal.
    add_index :raif_conversation_entries, :tools_dispatched_at, **options
  end
end
