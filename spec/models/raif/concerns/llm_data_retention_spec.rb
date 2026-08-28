# frozen_string_literal: true

require "rails_helper"

# Defined here rather than in spec/support: lib/raif/rspec.rb exports that file
# to host apps, and a class that opts out of the app-wide retention posture is
# exactly what a host app's own guard against opting out would trip over.
class Raif::TestProviderRetentionTask < Raif::Task
  self.open_ai_store_responses = true
  self.open_router_data_collection = "allow"
  self.open_router_zdr = false

  def build_prompt
    "Tell me a joke"
  end
end

# The inverse: a task whose prompts must not be retained, on an app whose
# global settings are permissive.
class Raif::TestSensitiveRetentionTask < Raif::Task
  self.open_ai_store_responses = false
  self.open_router_data_collection = "deny"
  self.open_router_zdr = true

  def build_prompt
    "Tell me a joke"
  end
end

RSpec.describe Raif::Concerns::LlmDataRetention do
  let(:creator) { FB.create(:raif_test_user) }

  describe "the class attributes" do
    it "is nil by default, so the class defers to Raif.config" do
      expect(Raif::TestTask.open_ai_store_responses).to be_nil
      expect(Raif::TestTask.open_router_data_collection).to be_nil
      expect(Raif::TestTask.open_router_zdr).to be_nil
      expect(Raif::Conversation.open_ai_store_responses).to be_nil
      expect(Raif::Agent.open_router_data_collection).to be_nil
    end

    it "carries a per-class override" do
      expect(Raif::TestProviderRetentionTask.open_ai_store_responses).to be(true)
      expect(Raif::TestProviderRetentionTask.open_router_data_collection).to eq("allow")
      expect(Raif::TestSensitiveRetentionTask.open_router_zdr).to be(true)
    end
  end

  describe "the settings on the model completion" do
    before { stub_raif_task(Raif::TestTask){ "a joke" } }

    it "leaves a task without an override on the config value" do
      task = Raif::TestTask.run(creator: creator)

      expect(task.raif_model_completion.open_ai_store_responses).to be(false)
      expect(task.raif_model_completion.open_router_data_collection).to eq("deny")
      expect(task.raif_model_completion.open_router_zdr).to be(false)
    end

    it "applies the task's override" do
      stub_raif_task(Raif::TestProviderRetentionTask){ "a joke" }
      task = Raif::TestProviderRetentionTask.run(creator: creator)

      expect(task.raif_model_completion.open_ai_store_responses).to be(true)
      expect(task.raif_model_completion.open_router_data_collection).to eq("allow")
    end
  end

  # Batch submission reloads its completions from the database, in a later
  # process, and builds the provider request from what it finds. An override
  # held only in memory would be lost there, and the loss is not symmetric: a
  # permissive global setting would then retain the prompts of a task that
  # explicitly said not to.
  describe "a batched completion, reloaded" do
    let(:batch) do
      Raif::ModelCompletionBatches::OpenAi.create!(
        llm_model_key: "open_ai_responses_gpt_4o",
        model_api_name: "gpt-4o",
        completion_handler_class_name: "Raif::TaskBatchCompletionHandler"
      )
    end

    before do
      allow(Raif.config).to receive(:open_ai_store_responses).and_return(true)
      allow(Raif.config).to receive(:open_router_data_collection).and_return("allow")
      allow(Raif.config).to receive(:open_router_zdr).and_return(false)
    end

    it "keeps a restrictive task override across the reload" do
      task = Raif::TestSensitiveRetentionTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "open_ai_responses_gpt_4o"
      )

      reloaded = Raif::ModelCompletion.find(task.raif_model_completion.id)

      expect(reloaded.open_ai_store_responses).to be(false)
      expect(reloaded.open_router_data_collection).to eq("deny")
      expect(reloaded.open_router_zdr).to be(true)

      parameters = Raif.llm(:open_ai_responses_gpt_4o).send(:build_request_parameters, reloaded)
      expect(parameters[:store]).to be(false)
    end

    it "still defers to the config value for a task with no override" do
      task = Raif::TestTask.build_for_batch(
        batch: batch,
        creator: creator,
        llm_model_key: "open_ai_responses_gpt_4o"
      )

      reloaded = Raif::ModelCompletion.find(task.raif_model_completion.id)

      expect(reloaded.open_ai_store_responses).to be(true)
      expect(reloaded.open_router_data_collection).to eq("allow")
      expect(reloaded.open_router_zdr).to be(false)
    end
  end
end
