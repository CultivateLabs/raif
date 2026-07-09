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
        batch_custom_id: "x1",
        model_api_name: "claude-haiku-4-5",
        llm_model_key: "anthropic_claude_4_5_haiku"
      )

      described_class.perform_now(batch.id)

      mc.reload
      expect(mc.failed?).to be(true)
      expect(mc.failure_reason).to include("canceled")

      expect(llm_double).not_to have_received(:fetch_batch_results!)
    end

    it "expires the batch when submitted_at is older than the configured max age (best-effort provider cancel + local fail)" do
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        b.update!(status: "in_progress")
        "in_progress"
      end
      allow(llm_double).to receive(:cancel_batch!)
      allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(1.hour)
      allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return([60.seconds])
      batch.update!(submitted_at: 2.hours.ago)

      mc = FB.create(
        :raif_model_completion,
        raif_model_completion_batch: batch,
        batch_custom_id: "x1",
        model_api_name: "claude-haiku-4-5",
        llm_model_key: "anthropic_claude_4_5_haiku"
      )

      expect do
        described_class.perform_now(batch.id)
      end.not_to have_enqueued_job(described_class)

      reloaded = batch.reload
      expect(reloaded.status).to eq("failed")
      expect(mc.reload.failed?).to be(true)
      expect(llm_double).to have_received(:cancel_batch!).with(batch)
    end

    it "reschedules itself (without raising) when the provider raises a transient/retriable error" do
      allow(llm_double).to receive(:fetch_batch_status!).and_raise(Faraday::ConnectionFailed.new("boom"))
      allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return([60.seconds, 2.minutes])
      allow(Raif.config).to receive(:model_completion_batch_max_age).and_return(26.hours)

      expect do
        described_class.perform_now(batch.id, attempt: 1)
      end.to have_enqueued_job(described_class).with(batch.id, attempt: 2)

      expect(batch.reload.next_poll_at).to be_within(5.seconds).of(60.seconds.from_now)
    end

    it "re-raises a non-transient error so the host's job adapter surfaces it" do
      allow(llm_double).to receive(:fetch_batch_status!).and_raise(StandardError, "non-transient")

      expect do
        expect do
          described_class.perform_now(batch.id, attempt: 1)
        end.to raise_error(StandardError, "non-transient")
      end.not_to have_enqueued_job(described_class)
    end

    describe "error notification" do
      # Hosts that load airbrake-ruby get notified via the global Airbrake
      # constant. We don't depend on the gem, so we stub a minimal interface to
      # pin the behavior: transient errors stay silent (they self-heal via
      # reschedule); non-transient errors notify before re-raising.
      let(:airbrake_stub) { class_double("Airbrake", build_notice: notice, notify: nil) }
      let(:notice) { { context: {}, params: {} } }

      before do
        stub_const("Airbrake", airbrake_stub)
      end

      it "does not notify Airbrake when a transient error reschedules the chain" do
        allow(llm_double).to receive(:fetch_batch_status!).and_raise(Faraday::ServerError.new("503 from provider"))
        allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return([60.seconds])

        described_class.perform_now(batch.id, attempt: 1)

        expect(airbrake_stub).not_to have_received(:notify)
      end

      it "does not notify Airbrake when a transient error fires against an already-finalized batch" do
        allow(llm_double).to receive(:fetch_batch_status!) do |b|
          Raif::ModelCompletionBatch.where(id: b.id).update_all(
            status: "failed", failed_at: Time.current, handler_dispatched_at: Time.current
          )
          raise Faraday::TimeoutError, "transient"
        end

        described_class.perform_now(batch.id, attempt: 1)

        expect(airbrake_stub).not_to have_received(:notify)
      end

      it "notifies Airbrake before re-raising a non-transient error" do
        allow(llm_double).to receive(:fetch_batch_status!).and_raise(StandardError, "non-transient")

        expect do
          described_class.perform_now(batch.id, attempt: 1)
        end.to raise_error(StandardError, "non-transient")

        expect(airbrake_stub).to have_received(:build_notice).once
        expect(airbrake_stub).to have_received(:notify).with(notice).once
        expect(notice[:context][:component]).to eq("raif_poll_model_completion_batch_job")
        expect(notice[:params]).to eq({ batch_id: batch.id })
      end
    end

    it "does not reschedule on transient error if the batch reloaded into terminal + handler already dispatched" do
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        # Simulate a separate process having fully finalized the batch concurrently:
        # in-memory batch is non-terminal, but the DB row is terminal AND
        # handler_dispatched_at is set (the safety sweep ran expire! +
        # dispatch_completion_handler! while we were in flight). No reason to
        # reschedule: the work is done.
        Raif::ModelCompletionBatch.where(id: b.id).update_all(
          status: "failed", failed_at: Time.current, handler_dispatched_at: Time.current
        )
        raise Faraday::TimeoutError, "transient"
      end

      expect do
        described_class.perform_now(batch.id, attempt: 1)
      end.not_to have_enqueued_job(described_class)
    end

    it "reschedules on transient error if the batch reloaded into terminal but handler is still pending" do
      # Mirrors the race where another process force-failed the batch but had
      # not yet dispatched the handler when our fetch_status! errored. The
      # rescheduled job's terminal-batch path will pick up the handler dispatch.
      allow(llm_double).to receive(:fetch_batch_status!) do |b|
        Raif::ModelCompletionBatch.where(id: b.id).update_all(status: "failed", failed_at: Time.current)
        raise Faraday::TimeoutError, "transient"
      end
      allow(Raif.config).to receive(:model_completion_batch_poll_schedule).and_return([60.seconds])

      expect do
        described_class.perform_now(batch.id, attempt: 1)
      end.to have_enqueued_job(described_class).with(batch.id, attempt: 2)
    end

    describe "terminal-batch finalize retry" do
      it "re-runs finalize! on a subsequent run when results_fetched_at is still NULL" do
        # Regression: under the prior code path, a fetch_batch_results! that
        # raised after fetch_batch_status! had committed the terminal status
        # would permanently strand the batch -- the next poll's
        # terminal-at-top branch dispatched the completion handler against
        # un-hydrated child completions. With finalize! now called in that
        # branch (and gated on results_fetched_at), the rescheduled run
        # retries fetch_batch_results! and the chain self-heals.
        stub_const("RetryFinalizeHandlerStub", Class.new do
          @calls = 0
          class << self
            attr_accessor :calls
          end

          def self.handle_batch_completion(_batch)
            self.calls += 1
          end
        end)

        batch.update!(
          status: "ended",
          ended_at: 1.minute.ago,
          completion_handler_class_name: "RetryFinalizeHandlerStub"
        )

        call_count = 0
        allow(llm_double).to receive(:fetch_batch_results!) do |_b|
          call_count += 1
          raise Faraday::BadRequestError, "transient 400" if call_count == 1
        end

        # First poll on the already-terminal batch: fetch_results! raises.
        # The job's rescue path re-raises (BadRequest isn't transient by default).
        expect do
          described_class.perform_now(batch.id)
        end.to raise_error(Faraday::BadRequestError)

        # results_fetched_at remained NULL, handler never dispatched.
        expect(batch.reload.results_fetched_at).to be_nil
        expect(batch.reload.handler_dispatched_at).to be_nil
        expect(RetryFinalizeHandlerStub.calls).to eq(0)

        # Second poll (ActiveJob retry / safety sweep / etc.): the provider
        # now responds cleanly, finalize! completes, handler dispatches.
        described_class.perform_now(batch.id)

        expect(call_count).to eq(2)
        expect(batch.reload.results_fetched_at).to be_present
        expect(batch.reload.handler_dispatched_at).to be_present
        expect(RetryFinalizeHandlerStub.calls).to eq(1)
      end
    end

    describe "terminal-batch handler retry" do
      it "re-dispatches the handler on a subsequent run when handler_dispatched_at is still NULL" do
        stub_const("RetryHandlerStub", Class.new do
          @calls = 0
          class << self
            attr_accessor :calls
            attr_accessor :raise_on_call
          end

          def self.handle_batch_completion(_batch)
            self.calls += 1
            raise "synthetic-handler-error" if @raise_on_call
          end
        end)

        batch.update!(status: "failed", failed_at: Time.current, completion_handler_class_name: "RetryHandlerStub")

        # First run: handler raises -> handler_dispatched_at stays NULL.
        RetryHandlerStub.raise_on_call = true
        expect do
          described_class.perform_now(batch.id)
        end.to raise_error("synthetic-handler-error")

        expect(RetryHandlerStub.calls).to eq(1)
        expect(batch.reload.handler_dispatched_at).to be_nil

        # Second run (host's job adapter retried us): handler succeeds and the
        # timestamp is set. Despite the batch already being terminal, the
        # job re-enters dispatch instead of short-circuiting.
        RetryHandlerStub.raise_on_call = false
        described_class.perform_now(batch.id)

        expect(RetryHandlerStub.calls).to eq(2)
        expect(batch.reload.handler_dispatched_at).to be_present
      end

      it "is a no-op for a terminal batch whose handler already ran successfully" do
        stub_const("AlreadyDispatchedHandlerStub", Class.new do
          @calls = 0
          class << self
            attr_accessor :calls
          end

          def self.handle_batch_completion(_batch)
            self.calls += 1
          end
        end)

        batch.update!(
          status: "ended",
          completion_handler_class_name: "AlreadyDispatchedHandlerStub",
          results_fetched_at: 1.minute.ago,
          handler_dispatched_at: 1.minute.ago
        )

        described_class.perform_now(batch.id)

        # Both gates set -- finalize! and dispatch_completion_handler! both
        # no-op, so the provider isn't touched and the handler isn't re-run.
        expect(AlreadyDispatchedHandlerStub.calls).to eq(0)
        expect(llm_double).not_to have_received(:fetch_batch_status!)
        expect(llm_double).not_to have_received(:fetch_batch_results!)
      end
    end
  end
end
