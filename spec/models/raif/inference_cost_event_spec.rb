# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: raif_inference_cost_events
#
#  id                             :bigint           not null, primary key
#  cache_creation_input_tokens    :integer
#  cache_read_input_tokens        :integer
#  completion_completed_at        :datetime
#  completion_failed_at           :datetime
#  completion_tokens              :integer
#  incurred_at                    :datetime         not null
#  llm_model_key                  :string           not null
#  metadata                       :jsonb
#  model_api_name                 :string           not null
#  output_token_cost              :decimal(10, 6)
#  prompt_token_cost              :decimal(10, 6)
#  prompt_tokens                  :integer
#  retry_count                    :integer          default(0), not null
#  source_class_name              :string
#  source_type                    :string
#  total_cost                     :decimal(10, 6)
#  total_tokens                   :integer
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  original_model_completion_id   :bigint           not null
#  raif_model_completion_batch_id :bigint
#  raif_model_completion_id       :bigint
#  source_id                      :bigint
#
# Indexes
#
#  index_raif_inference_cost_events_on_incurred_at                (incurred_at)
#  index_raif_inference_cost_events_on_original_completion_id     (original_model_completion_id)
#  index_raif_inference_cost_events_on_raif_model_completion_id   (raif_model_completion_id) UNIQUE
#  index_raif_inference_cost_events_on_source_type_and_source_id  (source_type,source_id)
#  index_raif_inference_cost_events_on_source_type_incurred_at    (source_type,incurred_at)
#
# Foreign Keys
#
#  fk_rails_...  (raif_model_completion_id => raif_model_completions.id) ON DELETE => nullify
#
RSpec.describe Raif::InferenceCostEvent, type: :model do
  describe "factory" do
    it "builds a valid event" do
      expect(FB.build(:raif_inference_cost_event)).to be_valid
    end
  end

  describe "validations" do
    it "requires original_model_completion_id, llm_model_key, model_api_name, and incurred_at" do
      event = described_class.new

      expect(event).not_to be_valid
      expect(event.errors[:original_model_completion_id]).to be_present
      expect(event.errors[:llm_model_key]).to be_present
      expect(event.errors[:model_api_name]).to be_present
      expect(event.errors[:incurred_at]).to be_present
    end

    it "does not require a source" do
      event = FB.build(:raif_inference_cost_event, source_type: nil, source_id: nil)
      expect(event).to be_valid
    end
  end

  describe "defaults" do
    it "initializes metadata to an empty hash" do
      expect(described_class.new.metadata).to eq({})
    end
  end

  describe "#model_completion_live?" do
    let(:model_completion) do
      FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
    end

    let!(:event) do
      FB.create(
        :raif_inference_cost_event,
        raif_model_completion: model_completion,
        original_model_completion_id: model_completion.id
      )
    end

    it "is true while the completion row exists" do
      expect(event.model_completion_live?).to eq(true)
    end

    it "flips to false when the completion is destroyed, keeping original_model_completion_id" do
      original_id = model_completion.id
      model_completion.destroy!

      event.reload
      expect(event.raif_model_completion_id).to be_nil
      expect(event.model_completion_live?).to eq(false)
      expect(event.original_model_completion_id).to eq(original_id)
    end

    it "flips to false when the completion is removed via delete_all (DB-level ON DELETE SET NULL)" do
      original_id = model_completion.id
      Raif::ModelCompletion.where(id: model_completion.id).delete_all

      event.reload
      expect(event.raif_model_completion_id).to be_nil
      expect(event.model_completion_live?).to eq(false)
      expect(event.original_model_completion_id).to eq(original_id)
    end
  end

  describe ".backfill!" do
    def create_completion(**attrs)
      FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        **attrs
      )
    end

    # The factory-created completions here are pre-existing rows without
    # events, so disable live sync while creating them.
    def without_live_sync
      allow(Raif.config).to receive(:inference_cost_events_enabled).and_return(false)
      results = yield
      allow(Raif.config).to receive(:inference_cost_events_enabled).and_call_original
      results
    end

    it "creates events for terminal completions only" do
      completed, failed, pending = without_live_sync do
        [
          create_completion(completed_at: 1.day.ago),
          create_completion(failed_at: 1.day.ago),
          create_completion,
        ]
      end

      expect do
        described_class.backfill!(batch_size: 2)
      end.to change(described_class, :count).by(2)

      expect(completed.reload.raif_inference_cost_event).to be_present
      expect(failed.reload.raif_inference_cost_event).to be_present
      expect(pending.reload.raif_inference_cost_event).to be_nil
    end

    it "skips completions that already have an event and is idempotent" do
      completion = without_live_sync { create_completion(completed_at: 1.day.ago) }

      described_class.backfill!
      event = completion.reload.raif_inference_cost_event

      expect do
        described_class.backfill!
      end.not_to change(described_class, :count)

      expect(completion.reload.raif_inference_cost_event).to eq(event)
    end

    it "tolerates a deleted source, falling back to source_type for source_class_name" do
      task = FB.create(:raif_test_task)
      completion = without_live_sync { create_completion(completed_at: 1.day.ago, source: task) }
      task.delete

      described_class.backfill!

      event = completion.reload.raif_inference_cost_event
      expect(event.source_type).to eq("Raif::Task")
      expect(event.source_id).to eq(task.id)
      expect(event.source_class_name).to eq("Raif::Task")
    end
  end
end
