# frozen_string_literal: true

class AddProviderDataRetentionToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    # Both nullable, and NULL means "use the Raif.config value". They have to
    # be persisted rather than request-scoped: batch submission reloads its
    # completions from the database, in a later process, and builds the
    # provider request from what it finds. A transient override would be lost
    # there - including a restrictive one set by a task whose prompts must not
    # be retained, on an app whose global setting is permissive.
    add_column :raif_model_completions, :open_ai_store_responses, :boolean
    add_column :raif_model_completions, :open_router_data_collection, :string
  end
end
