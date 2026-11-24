# frozen_string_literal: true

# Index-only migration, split from AddDurableRunColumns so the indexes can
# build without blocking writes on PostgreSQL. Each index commits on its own, so
# a retry after a failure skips the indexes that already exist. On PostgreSQL a
# failed concurrent build leaves an INVALID index under the same name: drop it
# by hand before the retry, or the retry skips it.
class IndexRaifModelToolInvocationsForDurableRuns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    options = { if_not_exists: true }
    options[:algorithm] = :concurrently if connection.adapter_name.downcase.include?("postg")

    add_index :raif_model_tool_invocations, :raif_agent_turn_id, **options
    # Deadline sweep: unfinished invocations whose deadline passed.
    add_index :raif_model_tool_invocations, :deadline_at, **options
    # Recovery sweep: entries that dispatched tool calls and are not yet terminal.
    add_index :raif_conversation_entries, :tools_dispatched_at, **options
  end
end
