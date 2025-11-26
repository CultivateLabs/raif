# frozen_string_literal: true

class AddProviderToolCallIdToRaifModelToolInvocations < ActiveRecord::Migration[8.0]
  def change
    add_column :raif_model_tool_invocations, :provider_tool_call_id, :string
  end
end
