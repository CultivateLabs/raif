# frozen_string_literal: true

class MakeRaifTaskCreatorOptional < ActiveRecord::Migration[7.1]
  def change
    change_column_null :raif_tasks, :creator_id, true
    change_column_null :raif_tasks, :creator_type, true
  end
end
