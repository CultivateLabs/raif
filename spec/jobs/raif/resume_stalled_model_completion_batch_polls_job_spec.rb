# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ResumeStalledModelCompletionBatchPollsJob, type: :job do
  describe "#perform" do
    it "enqueues a poll job for non-terminal batches whose next_poll_at is past the grace window" do
      stalled = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "in_progress",
        provider_batch_id: "msgbatch_stalled",
        submitted_at: 1.hour.ago,
        started_at: 1.hour.ago,
        next_poll_at: 30.minutes.ago
      )

      expect do
        described_class.perform_now
      end.to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(stalled.id)
    end

    it "skips batches that have already reached a terminal status" do
      ended = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "ended",
        provider_batch_id: "msgbatch_ended",
        submitted_at: 1.hour.ago,
        ended_at: 30.minutes.ago,
        next_poll_at: 30.minutes.ago
      )

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(ended.id)
    end

    it "skips batches whose next_poll_at is in the future" do
      not_yet_due = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "in_progress",
        provider_batch_id: "msgbatch_future",
        submitted_at: 5.minutes.ago,
        started_at: 5.minutes.ago,
        next_poll_at: 2.minutes.from_now
      )

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(not_yet_due.id)
    end

    it "skips batches whose next_poll_at is in the past but within the grace window" do
      within_grace = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "in_progress",
        provider_batch_id: "msgbatch_grace",
        submitted_at: 10.minutes.ago,
        started_at: 10.minutes.ago,
        next_poll_at: 30.seconds.ago
      )

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(within_grace.id)
    end

    it "skips batches with a null next_poll_at (never scheduled)" do
      no_poll = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "in_progress",
        provider_batch_id: "msgbatch_nopoll",
        submitted_at: 1.hour.ago,
        started_at: 1.hour.ago,
        next_poll_at: nil
      )

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(no_poll.id)
    end

    it "rescues per-batch so a single enqueue failure does not block recovery of later batches" do
      first = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "in_progress",
        provider_batch_id: "msgbatch_bad",
        submitted_at: 1.hour.ago,
        started_at: 1.hour.ago,
        next_poll_at: 30.minutes.ago
      )
      second = FB.create(
        :raif_model_completion_batch_anthropic,
        status: "in_progress",
        provider_batch_id: "msgbatch_good",
        submitted_at: 1.hour.ago,
        started_at: 1.hour.ago,
        next_poll_at: 29.minutes.ago
      )

      # find_each iterates ordered by primary key, so `first` is processed
      # before `second`. Stub perform_later to raise for the first batch only.
      allow(Raif::PollModelCompletionBatchJob).to receive(:perform_later).and_call_original
      allow(Raif::PollModelCompletionBatchJob).to receive(:perform_later).with(first.id).and_raise(StandardError, "synthetic queue failure")
      allow(Raif.logger).to receive(:error)

      expect do
        described_class.perform_now
      end.to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(second.id)

      expect(Raif.logger).to have_received(:error)
        .with(a_string_matching(/failed to enqueue poll for batch ##{first.id}.*synthetic queue failure/))
    end
  end
end
