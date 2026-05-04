# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ModelCompletionBatch, type: :model do
  describe "validations" do
    it "requires type, llm_model_key, model_api_name, and a known status" do
      batch = Raif::ModelCompletionBatches::Anthropic.new(
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-latest"
      )
      expect(batch).to be_valid

      batch.status = "bogus"
      expect(batch).not_to be_valid
      expect(batch.errors[:status]).to include("is not included in the list")
    end
  end

  describe "defaults" do
    it "initializes jsonb columns as empty hashes" do
      batch = Raif::ModelCompletionBatches::Anthropic.new(
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-latest"
      )
      expect(batch.metadata).to eq({})
      expect(batch.provider_response).to eq({})
      expect(batch.request_counts).to eq({})
    end

    it "defaults status to pending" do
      batch = Raif::ModelCompletionBatches::Anthropic.new(
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-latest"
      )
      expect(batch.status).to eq("pending")
      expect(batch.terminal?).to be(false)
    end
  end

  describe "STI subclasses" do
    it "persists Raif::ModelCompletionBatches::Anthropic and exposes its provider accessors" do
      batch = FB.create(
        :raif_model_completion_batch_anthropic,
        provider_response: { "results_url" => "https://api.anthropic.com/v1/messages/batches/foo/results", "cancel_url" => "x" }
      )
      reloaded = Raif::ModelCompletionBatch.find(batch.id)
      expect(reloaded).to be_a(Raif::ModelCompletionBatches::Anthropic)
      expect(reloaded.results_url).to eq("https://api.anthropic.com/v1/messages/batches/foo/results")
      expect(reloaded.cancel_url).to eq("x")
    end

    it "persists Raif::ModelCompletionBatches::OpenAi and exposes its provider accessors" do
      batch = FB.create(
        :raif_model_completion_batch_open_ai_responses,
        provider_response: {
          "input_file_id" => "file_in",
          "output_file_id" => "file_out",
          "error_file_id" => "file_err",
          "endpoint" => "/v1/responses"
        }
      )
      reloaded = Raif::ModelCompletionBatch.find(batch.id)
      expect(reloaded).to be_a(Raif::ModelCompletionBatches::OpenAi)
      expect(reloaded.input_file_id).to eq("file_in")
      expect(reloaded.output_file_id).to eq("file_out")
      expect(reloaded.error_file_id).to eq("file_err")
      expect(reloaded.endpoint).to eq("/v1/responses")
    end
  end

  describe "status helpers" do
    it "treats ended/canceled/expired/failed as terminal" do
      batch = FB.build(:raif_model_completion_batch_anthropic)
      Raif::ModelCompletionBatch::TERMINAL_STATUSES.each do |s|
        batch.status = s
        expect(batch.terminal?).to be(true), "expected #{s} to be terminal"
      end

      (Raif::ModelCompletionBatch::STATUSES - Raif::ModelCompletionBatch::TERMINAL_STATUSES).each do |s|
        batch.status = s
        expect(batch.terminal?).to be(false), "expected #{s} to not be terminal"
      end
    end

    it "scopes due_for_poll to non-terminal batches with next_poll_at <= now" do
      due = FB.create(:raif_model_completion_batch_anthropic, status: "in_progress", next_poll_at: 1.minute.ago)
      future = FB.create(:raif_model_completion_batch_anthropic, status: "in_progress", next_poll_at: 1.hour.from_now)
      done = FB.create(:raif_model_completion_batch_anthropic, status: "ended", next_poll_at: 1.minute.ago)

      ids = Raif::ModelCompletionBatch.due_for_poll.pluck(:id)
      expect(ids).to include(due.id)
      expect(ids).not_to include(future.id, done.id)
    end
  end

  describe "child completion association" do
    it "lets a Raif::ModelCompletion belong to a batch" do
      batch = FB.create(:raif_model_completion_batch_anthropic)
      mc = FB.create(
        :raif_model_completion,
        raif_model_completion_batch: batch,
        batch_custom_id: "task_42",
        model_api_name: "claude-3-5-haiku-latest",
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(batch.reload.raif_model_completions).to include(mc)
      expect(mc.reload.raif_model_completion_batch).to eq(batch)
      expect(mc.batch_custom_id).to eq("task_42")
    end

    it "Raif::ModelCompletion#pending? is true when no started_at/completed_at/failed_at is set" do
      mc = Raif::ModelCompletion.new
      expect(mc.pending?).to be(true)

      mc.started_at = Time.current
      expect(mc.pending?).to be(false)
    end
  end

  describe "#dispatch_completion_handler!" do
    let(:batch) { FB.create(:raif_model_completion_batch_anthropic) }

    it "is a no-op when completion_handler_class_name is blank" do
      batch.update!(completion_handler_class_name: nil)
      expect { batch.dispatch_completion_handler! }.not_to raise_error
    end

    it "calls handle_batch_completion on the resolved class" do
      stub_const("BatchCompletionHandlerStub", Class.new do
        def self.handle_batch_completion(batch)
          @last_batch = batch
        end

        class << self
          attr_reader :last_batch
        end
      end)

      batch.update!(completion_handler_class_name: "BatchCompletionHandlerStub")
      batch.dispatch_completion_handler!
      expect(BatchCompletionHandlerStub.last_batch).to eq(batch)
    end

    it "logs and skips when the class name does not resolve" do
      batch.update!(completion_handler_class_name: "NoSuchHandlerClassXYZ")
      expect(Raif.logger).to receive(:error).with(a_string_matching(/could not be resolved/))
      expect { batch.dispatch_completion_handler! }.not_to raise_error
    end
  end

  describe "consumer-facing façade (#submit! / #fetch_status! / #fetch_results!)" do
    let(:batch) { FB.create(:raif_model_completion_batch_anthropic) }
    let(:llm_double) { instance_double(Raif::Llms::Anthropic) }

    before do
      allow(batch).to receive(:llm).and_return(llm_double)
    end

    it "#submit! delegates to llm.submit_batch!(self) and auto-enqueues the polling job" do
      allow(llm_double).to receive(:submit_batch!)

      expect do
        batch.submit!
      end.to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(batch.id)

      expect(llm_double).to have_received(:submit_batch!).with(batch)
      expect(batch.reload.next_poll_at).to be_within(5.seconds).of(60.seconds.from_now)
    end

    it "#submit!(enqueue_poll: false) skips the polling-job auto-enqueue" do
      allow(llm_double).to receive(:submit_batch!)

      expect do
        batch.submit!(enqueue_poll: false)
      end.not_to have_enqueued_job(Raif::PollModelCompletionBatchJob)

      expect(batch.reload.next_poll_at).to be_nil
    end

    it "#fetch_status! delegates to llm.fetch_batch_status!(self)" do
      allow(llm_double).to receive(:fetch_batch_status!).and_return("in_progress")
      expect(batch.fetch_status!).to eq("in_progress")
      expect(llm_double).to have_received(:fetch_batch_status!).with(batch)
    end

    it "#fetch_results! delegates to llm.fetch_batch_results!(self)" do
      allow(llm_double).to receive(:fetch_batch_results!)
      batch.fetch_results!
      expect(llm_double).to have_received(:fetch_batch_results!).with(batch)
    end

    it "#cancel! delegates to llm.cancel_batch!(self)" do
      allow(llm_double).to receive(:cancel_batch!).and_return("in_progress")
      expect(batch.cancel!).to eq("in_progress")
      expect(llm_double).to have_received(:cancel_batch!).with(batch)
    end
  end

  describe "Raif::Llm.supports_batch_inference?" do
    it "defaults to false" do
      expect(Raif::Llm.supports_batch_inference?).to be(false)
    end

    it "is true for classes that include Raif::Concerns::Llms::SupportsBatchInference" do
      klass = Class.new(Raif::Llm) do
        include Raif::Concerns::Llms::SupportsBatchInference
      end
      expect(klass.supports_batch_inference?).to be(true)
    end
  end

  describe "#assert_submittable! (re-submit guard)" do
    it "permits a fresh pending batch with no provider_batch_id" do
      batch = FB.build(:raif_model_completion_batch_anthropic, status: "pending", provider_batch_id: nil)
      expect { batch.assert_submittable! }.not_to raise_error
    end

    it "raises if the batch already has a provider_batch_id" do
      batch = FB.build(
        :raif_model_completion_batch_anthropic,
        status: "pending",
        provider_batch_id: "msgbatch_already_submitted"
      )
      expect { batch.assert_submittable! }.to raise_error(Raif::Errors::InvalidBatchError, /not submittable/)
    end

    it "raises if the batch has moved past `pending`" do
      Raif::ModelCompletionBatch::STATUSES.each do |status|
        next if status == "pending"

        batch = FB.build(:raif_model_completion_batch_anthropic, status: status, provider_batch_id: nil)
        expect { batch.assert_submittable! }.to raise_error(Raif::Errors::InvalidBatchError, /not submittable/),
          "expected status=#{status} to be rejected"
      end
    end
  end

  describe "#force_fail! transactional rollback" do
    it "rolls back the batch-status update if a child completion write raises mid-loop" do
      batch = FB.create(:raif_model_completion_batch_anthropic, status: "in_progress", started_at: 1.minute.ago)
      mc = FB.create(
        :raif_model_completion,
        raif_model_completion_batch: batch,
        batch_custom_id: "x1",
        model_api_name: "claude-3-5-haiku-latest",
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      # Simulate a child write blowing up mid-iteration. With the transaction
      # in place, the batch-row update should also roll back so a future
      # poll/sweep can re-enter this code path.
      allow_any_instance_of(Raif::ModelCompletion).to receive(:failed!).and_raise(StandardError, "synthetic")

      expect do
        batch.force_fail!(reason: "synthetic")
      end.to raise_error(StandardError, "synthetic")

      expect(batch.reload.status).to eq("in_progress")
      expect(batch.failed_at).to be_nil
      expect(mc.reload).not_to be_failed
    end
  end

  describe "#recalculate_costs!" do
    it "logs and skips when there are no child completions" do
      batch = FB.create(:raif_model_completion_batch_anthropic)
      expect(Raif.logger).to receive(:warn).with(a_string_matching(/no child raif_model_completions/))
      expect { batch.recalculate_costs! }.not_to(change { batch.reload.attributes.slice("prompt_token_cost", "output_token_cost", "total_cost") })
    end

    it "logs and skips when all aggregate cost columns are NULL (so existing values aren't nulled out)" do
      batch = FB.create(
        :raif_model_completion_batch_anthropic,
        prompt_token_cost: 0.001,
        output_token_cost: 0.002,
        total_cost: 0.003
      )
      mc = FB.create(
        :raif_model_completion,
        raif_model_completion_batch: batch,
        batch_custom_id: "x1",
        model_api_name: "claude-3-5-haiku-latest",
        llm_model_key: "anthropic_claude_3_5_haiku"
      )
      # Make sure the child completion has NULL cost columns. The factory's
      # prompt_tokens/completion_tokens trigger calculate_costs, so we null
      # them out via update_columns (skipping callbacks).
      mc.update_columns(prompt_token_cost: nil, output_token_cost: nil, total_cost: nil)

      expect(Raif.logger).to receive(:warn).with(a_string_matching(/NULL or zero/))
      batch.recalculate_costs!

      reloaded = batch.reload
      expect(reloaded.prompt_token_cost.to_f).to eq(0.001)
      expect(reloaded.output_token_cost.to_f).to eq(0.002)
      expect(reloaded.total_cost.to_f).to eq(0.003)
    end
  end
end
