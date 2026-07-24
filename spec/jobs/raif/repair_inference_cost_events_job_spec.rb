# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::RepairInferenceCostEventsJob, type: :job do
  it "creates missing events for terminal completions" do
    # Simulate a completion whose live sync failed: terminal, but no event.
    allow(Raif.config).to receive(:inference_cost_events_enabled).and_return(false)
    completion = FB.create(
      :raif_model_completion,
      llm_model_key: "raif_test_llm",
      model_api_name: "raif-test-llm",
      completed_at: 1.hour.ago
    )
    allow(Raif.config).to receive(:inference_cost_events_enabled).and_call_original

    expect do
      described_class.perform_now
    end.to change(Raif::InferenceCostEvent, :count).by(1)

    event = completion.reload.raif_inference_cost_event
    expect(event).to be_present
    expect(event.original_model_completion_id).to eq(completion.id)
    expect(event.incurred_at).to eq(completion.created_at)
  end

  it "is a no-op when nothing is missing" do
    expect do
      described_class.perform_now
    end.not_to change(Raif::InferenceCostEvent, :count)
  end

  it "retries through the queue backend when the backfill leaves records unsynced, instead of reporting success" do
    allow(Raif.config).to receive(:inference_cost_events_enabled).and_return(false)
    FB.create(
      :raif_model_completion,
      llm_model_key: "raif_test_llm",
      model_api_name: "raif-test-llm",
      completed_at: 1.hour.ago
    )
    allow(Raif.config).to receive(:inference_cost_events_enabled).and_call_original

    allow_any_instance_of(Raif::ModelCompletion).to receive(:create_or_update_inference_cost_event!)
      .and_raise(ActiveRecord::StatementInvalid, "transient failure")

    # retry_on intercepts the error and re-enqueues the job with backoff
    # rather than swallowing the failure.
    expect do
      described_class.perform_now
    end.to have_enqueued_job(described_class)
  end
end
