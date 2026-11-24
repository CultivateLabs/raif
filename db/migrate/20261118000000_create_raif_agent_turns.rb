# frozen_string_literal: true

# One row per agent turn. The row is the durable record of how far the turn
# got, so a job that runs again continues from the saved state and does not
# repeat a model call or a tool call that already happened.
class CreateRaifAgentTurns < ActiveRecord::Migration[7.1]
  def change
    create_table :raif_agent_turns do |t|
      t.bigint :raif_agent_id, null: false
      # Equal to the agent's iteration_count while this turn is current.
      t.integer :iteration, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :raif_model_completion_id
      t.datetime :started_at
      t.datetime :tools_completed_at
      t.datetime :completed_at

      t.timestamps
    end

    # Unique: two jobs that both try to open the same turn cannot both succeed.
    add_index :raif_agent_turns, [:raif_agent_id, :iteration], unique: true
    # Recovery sweep: unfinished turns that have not changed for a while.
    add_index :raif_agent_turns, [:status, :updated_at]
  end
end
