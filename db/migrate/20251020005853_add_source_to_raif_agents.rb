# frozen_string_literal: true

class AddSourceToRaifAgents < ActiveRecord::Migration[7.1]
  def change
    add_reference :raif_agents, :source, polymorphic: true, index: true
  end
end
