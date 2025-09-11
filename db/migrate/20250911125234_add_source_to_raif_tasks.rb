# frozen_string_literal: true

class AddSourceToRaifTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :raif_tasks, :source, polymorphic: true, index: true
  end
end
