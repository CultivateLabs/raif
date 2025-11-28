# frozen_string_literal: true

class AddProviderToolCallIdToRaifModelToolInvocations < ActiveRecord::Migration[7.2]
  def change
    add_column :raif_model_tool_invocations, :provider_tool_call_id, :string
  end
end
