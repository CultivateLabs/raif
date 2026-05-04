# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PollModelCompletionBatchJob, type: :job do
  let(:creator) { FB.build(:raif_test_user) }
  let(:batch) do
    FB.create(
      :raif_model_completion_batch_anthropic,
      provider_batch_id: "msgbatch_poll_test",
      status: "submitted",
      submitted_at: 1.minute.ago,
      started_at: 1.minute.ago
    )
  end

  let(:llm_double) do
    instance_double(Raif::Llms::Anthropic).tap do |dbl|
      allow(dbl).to receive(:fetch_batch_status!, &:status)
      allow(dbl).to receive(:fetch_batch_results!)
    end
  end

  before do
    allow(batch).to receive(:llm).and_return(llm_double)
    allow(Raif::ModelCompletionBatch).to receive(:find_by).and_call_original
    allow(Raif::ModelCompletionBatch).to receive(:find_by).with(id: batch.id).and_return(batch)
    allow(Raif::ModelCompletionBatch).to receive(:find_by).with(id: -1).and_call_original
  end

  describe "#perform" do
    it "is a no-op when the batch row is missing" do
      expect { described_class.perform_now(-1) }.not_to raise_error
      expect(llm_double).not_to have_received(:fetch_batch_status!)
    end

    it "is a no-op when the batch is already terminal" do
      batch.update!(status: "ended")

      described_class.perform_now(batch.id)

      expect(llm_double).not_to have_received(:fetch_batch_status!)
    end

    it "self-reschedules with the next backoff delay when the batch is still in progress" do
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        b.update!(status: "in_progress")
        "in_progress"
      end

      schedule = [60.seconds, 2.minutes, 5.minutes]
      allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return(schedule)
      allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(26.hours)

      expect do
        described_class.perform_now(batch.id, attempt: 1)
      end.to have_enqueued_job(described_class).with(batch.id, attempt: 2)

      expect(batch.reload.next_poll_at).to be_within(5.seconds).of(60.seconds.from_now)
    end

    it "uses the next entry in the schedule for subsequent attempts and clamps to the last entry" do
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        b.update!(status: "in_progress")
        "in_progress"
      end
      schedule = [60.seconds, 2.minutes, 5.minutes]
      allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return(schedule)
      allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(26.hours)

      described_class.perform_now(batch.id, attempt: 4) # past end of schedule
      expect(batch.reload.next_poll_at).to be_within(5.seconds).of(5.minutes.from_now)
    end

    it "fetches results and dispatches the completion handler when the batch transitions to ended" do
      stub_const("PollHandlerStub", Class.new do
        def self.handle_batch_completion(batch)
          @last_batch = batch
        end

        class << self
          attr_reader :last_batch
        end
      end)

      batch.update!(completion_handler_class_name: "PollHandlerStub")

      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        b.update!(status: "ended")
        "ended"
      end

      expect do
        described_class.perform_now(batch.id)
      end.not_to have_enqueued_job(described_class)

      expect(llm_double).to have_received(:fetch_batch_results!).with(batch)
      expect(PollHandlerStub.last_batch).to eq(batch)
    end

    it "force-fails the batch when status transitions to canceled, expired, or failed" do
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        b.update!(status: "canceled", ended_at: Time.current)
        "canceled"
      end

      mc = FB.create(
        :raif_model_completion,
        raif_model_completion_batch: batch,
        provider_request_id: "x1",
        model_api_name: "claude-3-5-haiku-latest",
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      described_class.perform_now(batch.id)

      mc.reload
      expect(mc.failed?).to be(true)
      expect(mc.failure_reason).to include("canceled")

      expect(llm_double).not_to have_received(:fetch_batch_results!)
    end

    it "force-fails when submitted_at is older than the configured max age" do
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        b.update!(status: "in_progress")
        "in_progress"
      end
      allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(1.hour)
      allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return([60.seconds])
      batch.update!(submitted_at: 2.hours.ago)

      mc = FB.create(
        :raif_model_completion,
        raif_model_completion_batch: batch,
        provider_request_id: "x1",
        model_api_name: "claude-3-5-haiku-latest",
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect do
        described_class.perform_now(batch.id)
      end.not_to have_enqueued_job(described_class)

      reloaded = batch.reload
      expect(reloaded.status).to eq("failed")
      expect(mc.reload.failed?).to be(true)
    end
  end
end
