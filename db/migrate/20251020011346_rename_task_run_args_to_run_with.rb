# frozen_string_literal: true

class RenameTaskRunArgsToRunWith < ActiveRecord::Migration[8.0]
  def change
    rename_column :raif_tasks, :task_run_args, :run_with
  end
end
