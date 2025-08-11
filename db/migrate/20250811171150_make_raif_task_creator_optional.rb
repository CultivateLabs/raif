# frozen_string_literal: true

class MakeRaifTaskCreatorOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :raif_tasks, :creator_id, true
    change_column_null :raif_tasks, :creator_type, true
  end
end
