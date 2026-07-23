# frozen_string_literal: true

namespace :raif do
  namespace :install do
    desc "Copy migrations from Raif to host application"
    task :migrations do
      ENV["FROM"] = "raif"
      Rake::Task["railties:install:migrations"].invoke
    end
  end

  desc "Create Raif::InferenceCostEvent records for terminal model completions that don't have one yet"
  task backfill_inference_cost_events: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", "500").to_i
    Raif::InferenceCostEvent.backfill!(batch_size: batch_size)
  end

  desc "Copy citations and llm_model_key from each conversation entry's newest model completion onto the entry"
  task backfill_conversation_entry_completion_fields: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", "500").to_i
    Raif::ConversationEntry.backfill_denormalized_completion_fields!(batch_size: batch_size)
  end
end
