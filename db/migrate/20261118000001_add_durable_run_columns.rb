# frozen_string_literal: true

# Transactional column additions only. The indexes on the (large in host apps)
# raif_model_tool_invocations table live in the next migration, which builds
# them concurrently on PostgreSQL.
class AddDurableRunColumns < ActiveRecord::Migration[7.1]
  def change
    # Fencing token for the current run. A job that carries an older token does nothing.
    add_column :raif_agents, :run_token, :string
    # "in_process" (run!) or "async" (run_later!). Recovery only resumes async runs.
    add_column :raif_agents, :run_mode, :string
    add_column :raif_agents, :canceled_at, :datetime

    add_column :raif_model_tool_invocations, :raif_agent_turn_id, :bigint
    # Order of the call in the model's response. Results reach the model in this order.
    add_column :raif_model_tool_invocations, :position, :integer
    # "automatic": complete when the tool returns. "deferred": complete when the host says so.
    add_column :raif_model_tool_invocations, :completion_mode, :string, null: false, default: "automatic"
    add_column :raif_model_tool_invocations, :started_at, :datetime
    add_column :raif_model_tool_invocations, :execution_token, :string
    add_column :raif_model_tool_invocations, :lease_expires_at, :datetime
    add_column :raif_model_tool_invocations, :deadline_at, :datetime
    add_column :raif_model_tool_invocations, :canceled_at, :datetime
    add_column :raif_model_tool_invocations, :failure_reason, :text

    add_column :raif_conversation_entries, :tools_dispatched_at, :datetime
    add_column :raif_conversation_entries, :tools_completed_at, :datetime
    # Set once the continuation after the entry's tool calls ran (callbacks,
    # follow-up entry). A completed entry without it still owes its continuation.
    add_column :raif_conversation_entries, :finalized_at, :datetime
  end
end
