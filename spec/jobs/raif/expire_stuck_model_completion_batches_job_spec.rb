# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ExpireStuckModelCompletionBatchesJob, type: :job do
  before do
    allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(26.hours)
  end

  it "force-fails non-terminal batches whose submitted_at is older than the max age and dispatches their handler" do
    stub_const("ExpireHandlerStub", Class.new do
      @batches = []

      class << self
        attr_reader :batches
      end

      def self.handle_batch_completion(batch)
        @batches << batch
      end
    end)

    stuck = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "in_progress",
      submitted_at: 30.hours.ago,
      started_at: 30.hours.ago,
      completion_handler_class_name: "ExpireHandlerStub"
    )

    fresh = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "in_progress",
      submitted_at: 5.minutes.ago,
      started_at: 5.minutes.ago,
      completion_handler_class_name: "ExpireHandlerStub"
    )

    already_done = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "ended",
      submitted_at: 30.hours.ago,
      ended_at: 6.hours.ago
    )

    stuck_mc = FB.create(
      :raif_model_completion,
      raif_model_completion_batch: stuck,
      provider_request_id: "stuck1",
      model_api_name: "claude-3-5-haiku-latest",
      llm_model_key: "anthropic_claude_3_5_haiku"
    )

    described_class.perform_now

    expect(stuck.reload.status).to eq("failed")
    expect(stuck.failed_at).to be_present
    expect(stuck.failure_reason).to include("max_age")

    expect(stuck_mc.reload.failed?).to be(true)
    expect(stuck_mc.failure_reason).to include("max_age")

    expect(fresh.reload.status).to eq("in_progress")
    expect(already_done.reload.status).to eq("ended")

    expect(ExpireHandlerStub.batches).to contain_exactly(stuck)
  end
end
