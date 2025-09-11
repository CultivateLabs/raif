# frozen_string_literal: true

class AddSourceToRaifTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :raif_tasks, :source, polymorphic: true, index: true
  end
end
