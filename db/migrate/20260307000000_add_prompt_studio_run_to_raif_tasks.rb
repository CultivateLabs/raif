# frozen_string_literal: true

class AddPromptStudioRunToRaifTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_tasks, :prompt_studio_run, :boolean, default: false, null: false
  end
end
