# frozen_string_literal: true

class AddRunWithToRaifAgents < ActiveRecord::Migration[8.0]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    add_column :raif_agents, :run_with, json_column_type
  end
end
