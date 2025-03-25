# frozen_string_literal: true

class CreateRaifTables < ActiveRecord::Migration[8.0]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    create_table :raif_tasks do |t|
      t.string :type, null: false, index: true
      t.text :prompt
      t.text :raw_response
      t.references :creator, polymorphic: true, null: false, index: true
      t.text :system_prompt
      t.string :requested_language_key
      t.integer :response_format, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.send json_column_type, :available_model_tools, null: false
      t.string :llm_model_key, null: false

      t.timestamps
    end

    create_table :raif_conversations do |t|
      t.string :llm_model_key, null: false
      t.references :creator, polymorphic: true, null: false, index: true
      t.string :requested_language_key
      t.string :type, null: false
      t.text :system_prompt
      t.send json_column_type, :available_model_tools, null: false
      t.send json_column_type, :available_user_tools, null: false
      t.integer :conversation_entries_count, default: 0, null: false

      t.timestamps
    end

    create_table :raif_conversation_entries do |t|
      t.references :raif_conversation, null: false, foreign_key: true
      t.references :creator, polymorphic: true, null: false, index: true
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.text :user_message
      t.text :raw_response
      t.text :model_response_message

      t.timestamps
    end

    create_table :raif_model_tool_invocations do |t|
      t.references :source, polymorphic: true, null: false, index: true
      t.string :tool_type, null: false
      t.send json_column_type, :tool_arguments, null: false
      t.send json_column_type, :result, null: false
      t.datetime :completed_at
      t.datetime :failed_at

      t.timestamps
    end

    create_table :raif_user_tool_invocations do |t|
      t.references :raif_conversation_entry, null: false, foreign_key: true
      t.string :type, null: false
      t.send json_column_type, :tool_settings, null: false

      t.timestamps
    end

    create_table :raif_agent_invocations do |t|
      t.string :type, null: false
      t.string :llm_model_key, null: false
      t.text :task
      t.text :system_prompt
      t.text :final_answer
      t.integer :max_iterations, default: 10, null: false
      t.integer :iteration_count, default: 0, null: false
      t.send json_column_type, :available_model_tools, null: false
      t.references :creator, polymorphic: true, null: false, index: true
      t.string :requested_language_key
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.text :failure_reason
      t.send json_column_type, :conversation_history, null: false

      t.timestamps
    end

    create_table :raif_model_completions do |t|
      t.references :source, polymorphic: true, index: true
      t.string :llm_model_key, null: false
      t.string :model_api_name, null: false
      t.send json_column_type, :available_model_tools, null: false
      t.send json_column_type, :messages, null: false
      t.text :system_prompt
      t.integer :response_format, default: 0, null: false
      t.string :response_format_parameter
      t.decimal :temperature, precision: 5, scale: 3
      t.integer :max_completion_tokens
      t.integer :completion_tokens
      t.integer :prompt_tokens
      t.text :raw_response
      t.send json_column_type, :response_tool_calls
      t.integer :total_tokens

      t.timestamps
    end
  end

end
