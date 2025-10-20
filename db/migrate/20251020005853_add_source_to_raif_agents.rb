# frozen_string_literal: true

class AddSourceToRaifAgents < ActiveRecord::Migration[8.0]
  def change
    add_reference :raif_agents, :source, polymorphic: true, index: true
  end
end
