# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ExpireStuckModelCompletionBatchesJob, type: :job do
  before do
    allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(26.hours)
  end

  it "expires non-terminal batches whose submitted_at is older than the max age, attempting a provider-side cancel, then dispatches their handler" do
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
      provider_batch_id: "msgbatch_stuck",
      submitted_at: 30.hours.ago,
      started_at: 30.hours.ago,
      completion_handler_class_name: "ExpireHandlerStub"
    )

    fresh = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "in_progress",
      provider_batch_id: "msgbatch_fresh",
      submitted_at: 5.minutes.ago,
      started_at: 5.minutes.ago,
      completion_handler_class_name: "ExpireHandlerStub"
    )

    already_done = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "ended",
      provider_batch_id: "msgbatch_done",
      submitted_at: 30.hours.ago,
      ended_at: 6.hours.ago
    )

    stuck_mc = FB.create(
      :raif_model_completion,
      raif_model_completion_batch: stuck,
      batch_custom_id: "stuck1",
      model_api_name: "claude-3-5-haiku-latest",
      llm_model_key: "anthropic_claude_3_5_haiku"
    )

    cancel_called_for = []
    allow_any_instance_of(Raif::Llms::Anthropic).to receive(:cancel_batch!) do |_llm, batch|
      cancel_called_for << batch.id
    end

    described_class.perform_now

    expect(stuck.reload.status).to eq("failed")
    expect(stuck.failed_at).to be_present
    expect(stuck.failure_reason).to include("max_age")

    expect(stuck_mc.reload.failed?).to be(true)
    expect(stuck_mc.failure_reason).to include("max_age")

    expect(fresh.reload.status).to eq("in_progress")
    expect(already_done.reload.status).to eq("ended")

    # Best-effort provider-side cancel was issued only for the stuck batch.
    # Fresh batches aren't expired; already-terminal batches are skipped by
    # the `non_terminal` scope and wouldn't receive a cancel even if reached.
    expect(cancel_called_for).to eq([stuck.id])

    expect(ExpireHandlerStub.batches).to contain_exactly(stuck)
  end

  it "rescues per-batch so one bad handler does not block expiry of later batches" do
    bad_handler = Class.new do
      def self.handle_batch_completion(_batch)
        raise StandardError, "synthetic handler failure"
      end
    end
    good_handler = Class.new do
      @batches = []
      class << self
        attr_reader :batches
      end
      def self.handle_batch_completion(batch)
        @batches << batch
      end
    end

    stub_const("BadExpireHandlerStub", bad_handler)
    stub_const("GoodExpireHandlerStub", good_handler)

    bad_batch = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "in_progress",
      provider_batch_id: "msgbatch_bad",
      submitted_at: 30.hours.ago,
      started_at: 30.hours.ago,
      completion_handler_class_name: "BadExpireHandlerStub"
    )

    good_batch = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "in_progress",
      provider_batch_id: "msgbatch_good",
      submitted_at: 30.hours.ago,
      started_at: 30.hours.ago,
      completion_handler_class_name: "GoodExpireHandlerStub"
    )

    allow_any_instance_of(Raif::Llms::Anthropic).to receive(:cancel_batch!)
    allow(Raif.logger).to receive(:error)

    described_class.perform_now

    # Both batches should have expired locally despite the bad handler raising.
    expect(bad_batch.reload.status).to eq("failed")
    expect(good_batch.reload.status).to eq("failed")

    # The good handler still ran for its own batch.
    expect(GoodExpireHandlerStub.batches).to contain_exactly(good_batch)

    # The failure was logged with the bad batch's id.
    expect(Raif.logger).to have_received(:error)
      .with(a_string_matching(/failed to expire batch ##{bad_batch.id}.*synthetic handler failure/))
  end

  it "still expires the batch locally when the provider-side cancel raises" do
    stub_const("ExpireHandlerStub", Class.new do
      def self.handle_batch_completion(_batch); end
    end)

    stuck = FB.create(
      :raif_model_completion_batch_anthropic,
      status: "in_progress",
      provider_batch_id: "msgbatch_stuck",
      submitted_at: 30.hours.ago,
      started_at: 30.hours.ago,
      completion_handler_class_name: "ExpireHandlerStub"
    )

    allow_any_instance_of(Raif::Llms::Anthropic).to receive(:cancel_batch!).and_raise(StandardError, "anthropic 503")
    allow(Raif.logger).to receive(:warn)

    described_class.perform_now

    expect(stuck.reload.status).to eq("failed")
    expect(Raif.logger).to have_received(:warn).with(a_string_matching(/best-effort provider-side cancel failed/))
  end
end
