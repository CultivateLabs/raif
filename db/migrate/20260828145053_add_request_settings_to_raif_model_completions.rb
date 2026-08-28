# frozen_string_literal: true

class AddRequestSettingsToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    # Sparse bag of provider request settings that have to survive to the
    # moment the request is built. Batch submission reloads its completions
    # from the database, in a later process, so a setting held only in memory
    # never reaches the wire for a batched request.
    #
    # A bag rather than a column per setting: each provider has its own knobs,
    # so typed columns would add one sparse, mostly-NULL column per provider
    # per knob. Raif::ModelCompletion::REQUEST_SETTING_KEYS is the allowed key
    # set and is validated, so the bag cannot become a dumping ground.
    add_column :raif_model_completions, :request_settings, :jsonb, null: false, default: {}
  end
end
