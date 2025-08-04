# frozen_string_literal: true

class AddTaskRunArgsToRaifTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_tasks, :task_run_args, :jsonb, default: {}
  end
end
