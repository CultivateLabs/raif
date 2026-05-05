# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Anthropic, "batch inference" do
  let(:llm) { Raif.llm(:anthropic_claude_3_5_haiku) }
  let(:creator) { FB.build(:raif_test_user) }
  let(:batch) do
    FB.create(
      :raif_model_completion_batch_anthropic,
      llm_model_key: "anthropic_claude_3_5_haiku",
      model_api_name: "claude-3-5-haiku-latest"
    )
  end

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
  end

  describe ".supports_batch_inference?" do
    it "is true for the Anthropic LLM class" do
      expect(Raif::Llms::Anthropic.supports_batch_inference?).to be(true)
    end
  end

  describe "#batch_class" do
    it "returns Raif::ModelCompletionBatches::Anthropic" do
      expect(llm.batch_class).to eq(Raif::ModelCompletionBatches::Anthropic)
    end
  end

  describe "#create_batch" do
    it "creates a persisted batch on the right STI subclass with the LLM's key and api_name pre-populated" do
      batch = llm.create_batch(
        completion_handler_class_name: "MyHandler",
        metadata: { "campaign_id" => 42 }
      )

      expect(batch).to be_a(Raif::ModelCompletionBatches::Anthropic)
      expect(batch).to be_persisted
      expect(batch.llm_model_key).to eq(llm.key.to_s)
      expect(batch.model_api_name).to eq(llm.api_name)
      expect(batch.completion_handler_class_name).to eq("MyHandler")
      expect(batch.metadata).to eq("campaign_id" => 42)
      expect(batch.status).to eq("pending")
    end

    it "forwards arbitrary attributes (e.g. creator) to the underlying record" do
      user = FB.create(:raif_test_user)
      batch = llm.create_batch(creator: user)
      expect(batch.creator).to eq(user)
    end
  end

  describe "#submit_batch!" do
    let!(:task1) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "task_1",
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )
    end

    let!(:task2) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "task_2",
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )
    end

    it "POSTs each child completion to /v1/messages/batches with build_request_parameters bodies + custom_id" do
      stub = stub_request(:post, "https://api.anthropic.com/v1/messages/batches")
        .with(headers: {
          "anthropic-version" => "2023-06-01",
          "anthropic-beta" => "message-batches-2024-09-24"
        })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            id: "msgbatch_abc123",
            processing_status: "in_progress",
            request_counts: { processing: 2, succeeded: 0, errored: 0, canceled: 0, expired: 0 },
            results_url: nil,
            cancel_url: "https://api.anthropic.com/v1/messages/batches/msgbatch_abc123/cancel"
          }.to_json
        )

      llm.submit_batch!(batch)

      expect(stub).to have_been_requested

      sent_body = nil
      WebMock::RequestRegistry.instance.requested_signatures.hash.each_key do |sig|
        next unless sig.uri.to_s.include?("/messages/batches") && sig.method == :post

        sent_body = JSON.parse(sig.body)
      end

      expect(sent_body).to be_present
      expect(sent_body["requests"].length).to eq(2)
      expect(sent_body["requests"].map { |r| r["custom_id"] }).to contain_exactly("task_1", "task_2")

      first = sent_body["requests"].first
      expect(first["params"]).to include("model" => "claude-3-5-haiku-latest")
      expect(first["params"]["messages"]).to eq([
        { "role" => "user", "content" => [{ "type" => "text", "text" => "Tell me a joke" }] }
      ])
      expect(first["params"]["system"]).to include("You are also good at telling jokes.")

      batch.reload
      expect(batch.provider_batch_id).to eq("msgbatch_abc123")
      expect(batch.status).to eq("in_progress")
      expect(batch.submitted_at).to be_present
      expect(batch.cancel_url).to eq("https://api.anthropic.com/v1/messages/batches/msgbatch_abc123/cancel")

      [task1, task2].each do |t|
        expect(t.raif_model_completion.reload.started_at).to be_present
      end
    end

    it "raises if a child completion has a blank batch_custom_id" do
      bad = batch.raif_model_completions.first
      bad.update_columns(batch_custom_id: nil)

      stub_request(:post, "https://api.anthropic.com/v1/messages/batches").to_return(status: 200, body: "{}")

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError)
    end

    it "raises (without making a network call) if the batch was already submitted" do
      batch.update!(status: "submitted", provider_batch_id: "msgbatch_already_submitted", submitted_at: 1.minute.ago)
      stub = stub_request(:post, "https://api.anthropic.com/v1/messages/batches")

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /not submittable/)
      expect(stub).not_to have_been_requested
    end
  end

  describe "#fetch_batch_status!" do
    let!(:running_batch) do
      FB.create(
        :raif_model_completion_batch_anthropic,
        provider_batch_id: "msgbatch_def456",
        status: "submitted",
        submitted_at: 1.minute.ago,
        started_at: 1.minute.ago
      )
    end

    it "maps in_progress / canceling to in_progress and ended to ended, recording results_url + ended_at" do
      stub_request(:get, "https://api.anthropic.com/v1/messages/batches/msgbatch_def456")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          id: "msgbatch_def456",
          processing_status: "in_progress",
          request_counts: { processing: 1, succeeded: 0, errored: 0, canceled: 0, expired: 0 },
          results_url: nil
        }.to_json)

      expect(llm.fetch_batch_status!(running_batch)).to eq("in_progress")
      expect(running_batch.reload.status).to eq("in_progress")
      expect(running_batch.ended_at).to be_nil

      stub_request(:get, "https://api.anthropic.com/v1/messages/batches/msgbatch_def456")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          id: "msgbatch_def456",
          processing_status: "ended",
          request_counts: { processing: 0, succeeded: 1, errored: 0, canceled: 0, expired: 0 },
          results_url: "https://api.anthropic.com/v1/messages/batches/msgbatch_def456/results"
        }.to_json)

      expect(llm.fetch_batch_status!(running_batch)).to eq("ended")
      reloaded = running_batch.reload
      expect(reloaded.status).to eq("ended")
      expect(reloaded.results_url).to eq("https://api.anthropic.com/v1/messages/batches/msgbatch_def456/results")
      expect(reloaded.ended_at).to be_present
    end

    it "logs a warning for an unknown processing_status and treats it as in_progress" do
      stub_request(:get, "https://api.anthropic.com/v1/messages/batches/msgbatch_def456")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          id: "msgbatch_def456",
          processing_status: "queued_in_some_new_state",
          request_counts: {}
        }.to_json)

      expect(Raif.logger).to receive(:warn).with(a_string_matching(/unknown Anthropic batch processing_status "queued_in_some_new_state"/))
      expect(llm.fetch_batch_status!(running_batch)).to eq("in_progress")
    end

    it "leaves an already-terminal batch alone even if the provider reports a non-terminal status (race guard)" do
      # Simulates the race where ExpireStuckModelCompletionBatchesJob force-failed
      # the batch between when this poll loaded it and when fetch_batch_status!
      # got the provider response back. Without the guard the failure would be
      # stomped back to whatever the provider reports.
      running_batch.update!(status: "failed", failed_at: Time.current, failure_reason: "max_age exceeded")

      stub_request(:get, "https://api.anthropic.com/v1/messages/batches/msgbatch_def456")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          id: "msgbatch_def456",
          processing_status: "in_progress",
          request_counts: { processing: 1, succeeded: 0, errored: 0, canceled: 0, expired: 0 }
        }.to_json)

      expect(llm.fetch_batch_status!(running_batch)).to eq("failed")
      expect(running_batch.reload.status).to eq("failed")
    end
  end

  describe "#cancel_batch!" do
    let!(:running_batch) do
      FB.create(
        :raif_model_completion_batch_anthropic,
        provider_batch_id: "msgbatch_cancel_target",
        status: "in_progress",
        submitted_at: 1.minute.ago,
        started_at: 1.minute.ago
      )
    end

    it "POSTs to /messages/batches/:id/cancel and updates status from the response" do
      stub = stub_request(:post, "https://api.anthropic.com/v1/messages/batches/msgbatch_cancel_target/cancel")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
          id: "msgbatch_cancel_target",
          processing_status: "canceling",
          request_counts: { processing: 1, succeeded: 0, errored: 0, canceled: 0, expired: 0 }
        }.to_json)

      expect(llm.cancel_batch!(running_batch)).to eq("in_progress")
      expect(stub).to have_been_requested
      expect(running_batch.reload.status).to eq("in_progress")
    end

    it "raises if the batch has no provider_batch_id (not yet submitted)" do
      pending_batch = FB.create(:raif_model_completion_batch_anthropic, status: "pending")
      expect { llm.cancel_batch!(pending_batch) }.to raise_error(Raif::Errors::InvalidBatchError, /no provider_batch_id/)
    end

    it "raises if the batch is already terminal" do
      running_batch.update!(status: "ended", ended_at: Time.current)
      expect { llm.cancel_batch!(running_batch) }.to raise_error(Raif::Errors::InvalidBatchError, /already terminal/)
    end
  end

  describe "#fetch_batch_results! / #apply_batch_result" do
    let!(:task_success) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "win",
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )
    end

    let!(:task_failure) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "lose",
        creator: creator,
        llm_model_key: "anthropic_claude_3_5_haiku"
      )
    end

    let(:results_url) { "https://api.anthropic.com/v1/messages/batches/msgbatch_xyz/results" }

    before do
      batch.update!(
        provider_batch_id: "msgbatch_xyz",
        status: "ended",
        provider_response: batch.provider_response.merge("results_url" => results_url)
      )
    end

    let(:jsonl_body) do
      [
        {
          custom_id: "win",
          result: {
            type: "succeeded",
            message: {
              id: "msg_aaa",
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "Why did the chicken cross the road? To get to the other side." }],
              usage: { input_tokens: 17, output_tokens: 12, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
            }
          }
        },
        {
          custom_id: "lose",
          result: {
            type: "errored",
            error: { type: "invalid_request_error", message: "Sample failure for batch test" }
          }
        }
      ].map(&:to_json).join("\n")
    end

    it "parses JSONL, populates the success completion, marks the failure completion failed, " \
      "applies the 50% discount, and recalculates batch costs" do
      stub_request(:get, results_url).to_return(status: 200, body: jsonl_body)

      llm.fetch_batch_results!(batch)

      win_mc = task_success.raif_model_completion.reload
      expect(win_mc.completed?).to be(true)
      expect(win_mc.raw_response).to eq("Why did the chicken cross the road? To get to the other side.")
      expect(win_mc.prompt_tokens).to eq(17)
      expect(win_mc.completion_tokens).to eq(12)
      expect(win_mc.total_tokens).to eq(29)

      # raif_model_completions costs are stored as decimal(10,6); compare with
      # tolerance loose enough to absorb the storage rounding for very small per-token costs.
      llm_config = Raif.llm_config(:anthropic_claude_3_5_haiku)
      expected_prompt_cost = (llm_config[:input_token_cost] * 17) * 0.5
      expected_output_cost = (llm_config[:output_token_cost] * 12) * 0.5
      expect(win_mc.prompt_token_cost.to_f).to be_within(1e-6).of(expected_prompt_cost.to_f)
      expect(win_mc.output_token_cost.to_f).to be_within(1e-6).of(expected_output_cost.to_f)
      expect(win_mc.total_cost.to_f).to be_within(1e-6).of((expected_prompt_cost + expected_output_cost).to_f)

      # The discount must actually have been applied: total cost < no-discount cost.
      no_discount_total = (llm_config[:input_token_cost] * 17) + (llm_config[:output_token_cost] * 12)
      expect(win_mc.total_cost.to_f).to be < no_discount_total.to_f

      lose_mc = task_failure.raif_model_completion.reload
      expect(lose_mc.failed?).to be(true)
      expect(lose_mc.failure_error).to include("errored")
      expect(lose_mc.failure_reason).to include("Sample failure")

      batch.reload
      expect(batch.total_cost.to_f).to be_within(1e-9).of(win_mc.total_cost.to_f)
    end

    it "logs and skips an unmatched custom_id without raising" do
      stub_request(:get, results_url).to_return(
        status: 200,
        body: { custom_id: "ghost", result: { type: "succeeded", message: { id: "x", content: [], usage: {} } } }.to_json
      )

      allow(Raif.logger).to receive(:warn)
      expect { llm.fetch_batch_results!(batch) }.not_to raise_error
      expect(Raif.logger).to have_received(:warn).with(a_string_matching(/did not match/))
    end

    it "raises when the batch has no results_url yet" do
      batch.update!(provider_response: batch.provider_response.merge("results_url" => nil))
      expect { llm.fetch_batch_results!(batch) }.to raise_error(Raif::Errors::InvalidBatchError)
    end

    it "fails any child completion that doesn't appear in the results stream" do
      partial_jsonl = [
        {
          custom_id: "win",
          result: {
            type: "succeeded",
            message: {
              id: "msg_aaa",
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "ok" }],
              usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
            }
          }
        }
      ].map(&:to_json).join("\n")

      stub_request(:get, results_url).to_return(status: 200, body: partial_jsonl)

      llm.fetch_batch_results!(batch)

      lose_mc = task_failure.raif_model_completion.reload
      expect(lose_mc.failed?).to be(true)
      expect(lose_mc.failure_error).to include("missing")
      expect(lose_mc.failure_reason).to include("not present in results stream")
    end
  end
end
