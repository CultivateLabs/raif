# frozen_string_literal: true

require "rails_helper"

# Defined here rather than in spec/support: lib/raif/rspec.rb exports that file
# to host apps, and a class that opts out of the app-wide retention posture is
# exactly what a host app's own guard against opting out would trip over.
class Raif::TestProviderRetentionTask < Raif::Task
  self.open_ai_store_responses = true
  self.open_router_data_collection = "allow"

  def build_prompt
    "Tell me a joke"
  end
end

RSpec.describe Raif::Concerns::LlmDataRetention do
  describe "the class attributes" do
    it "is nil by default, so the class defers to Raif.config" do
      expect(Raif::TestTask.open_ai_store_responses).to be_nil
      expect(Raif::TestTask.open_router_data_collection).to be_nil
      expect(Raif::Conversation.open_ai_store_responses).to be_nil
      expect(Raif::Agent.open_router_data_collection).to be_nil
    end

    it "carries a per-class override" do
      expect(Raif::TestProviderRetentionTask.open_ai_store_responses).to be(true)
      expect(Raif::TestProviderRetentionTask.open_router_data_collection).to eq("allow")
    end
  end

  # The settings are request-scoped rather than persisted, and Raif::Task
  # #process_completion! hands back a `becomes`-copy that does not carry them,
  # so these assert on the completion the adapter itself received.
  describe "the settings the adapter receives" do
    let(:dispatched) { [] }

    def run(task_class)
      stub_raif_task(task_class) do |_messages, model_completion, _source|
        dispatched << model_completion
        "a joke"
      end

      task_class.run(creator: FB.create(:raif_test_user))
      dispatched.last
    end

    it "leaves a task without an override on the config value" do
      model_completion = run(Raif::TestTask)

      expect(model_completion.open_ai_store_responses).to be(false)
      expect(model_completion.open_router_data_collection).to eq("deny")
    end

    it "applies the task's override" do
      model_completion = run(Raif::TestProviderRetentionTask)

      expect(model_completion.open_ai_store_responses).to be(true)
      expect(model_completion.open_router_data_collection).to eq("allow")
    end
  end
end
