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
        provider_request_id: "task_42",
        model_api_name: "claude-3-5-haiku-latest",
        llm_model_key: "anthropic_claude_3_5_haiku"
      )

      expect(batch.reload.raif_model_completions).to include(mc)
      expect(mc.reload.raif_model_completion_batch).to eq(batch)
      expect(mc.provider_request_id).to eq("task_42")
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
end
