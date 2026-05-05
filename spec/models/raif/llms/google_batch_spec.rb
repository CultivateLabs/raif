# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Google, "batch inference" do
  let(:llm) { Raif.llm(:google_gemini_2_5_flash) }
  let(:creator) { FB.build(:raif_test_user) }
  let(:batch) do
    FB.create(
      :raif_model_completion_batch_google,
      llm_model_key: "google_gemini_2_5_flash",
      model_api_name: "gemini-2.5-flash"
    )
  end

  let(:base_url) { "https://generativelanguage.googleapis.com/v1beta" }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
  end

  describe ".supports_batch_inference?" do
    it "is true for the Google LLM class" do
      expect(Raif::Llms::Google.supports_batch_inference?).to be(true)
    end
  end

  describe "#batch_class" do
    it "returns Raif::ModelCompletionBatches::Google" do
      expect(llm.batch_class).to eq(Raif::ModelCompletionBatches::Google)
    end
  end

  describe "#create_batch" do
    it "creates a persisted batch on the right STI subclass with the LLM's key and api_name pre-populated" do
      batch = llm.create_batch(
        completion_handler_class_name: "MyHandler",
        metadata: { "campaign_id" => 42 }
      )

      expect(batch).to be_a(Raif::ModelCompletionBatches::Google)
      expect(batch).to be_persisted
      expect(batch.llm_model_key).to eq(llm.key.to_s)
      expect(batch.model_api_name).to eq(llm.api_name)
      expect(batch.completion_handler_class_name).to eq("MyHandler")
      expect(batch.metadata).to eq("campaign_id" => 42)
      expect(batch.status).to eq("pending")
    end
  end

  describe "#submit_batch!" do
    let!(:task1) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "task_1",
        creator: creator,
        llm_model_key: "google_gemini_2_5_flash"
      )
    end

    let!(:task2) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "task_2",
        creator: creator,
        llm_model_key: "google_gemini_2_5_flash"
      )
    end

    let(:create_endpoint) { "#{base_url}/models/gemini-2.5-flash:batchGenerateContent" }

    it "POSTs to :batchGenerateContent with one inlined request per child completion, each tagged with its batch_custom_id" do
      stub = stub_request(:post, create_endpoint)
        .with(headers: { "x-goog-api-key" => Raif.config.google_api_key })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            name: "batches/op_abc123",
            metadata: { state: "JOB_STATE_PENDING", batchStats: { submittedRequestCount: 2 } },
            done: false
          }.to_json
        )

      llm.submit_batch!(batch)

      expect(stub).to have_been_requested

      sent_body = nil
      WebMock::RequestRegistry.instance.requested_signatures.hash.each_key do |sig|
        next unless sig.uri.to_s.include?(":batchGenerateContent") && sig.method == :post

        sent_body = JSON.parse(sig.body)
      end

      expect(sent_body).to be_present
      requests = sent_body.dig("batch", "input_config", "requests", "requests")
      expect(requests.length).to eq(2)
      expect(requests.map { |r| r.dig("metadata", "key") }).to contain_exactly("task_1", "task_2")

      first = requests.first
      expect(first["request"]).to include("contents")
      expect(first["request"]["contents"]).to be_an(Array)
      expect(first["request"]["system_instruction"]["parts"].first["text"]).to include("You are also good at telling jokes.")

      batch.reload
      expect(batch.provider_batch_id).to eq("op_abc123")
      expect(batch.operation_name).to eq("batches/op_abc123")
      expect(batch.status).to eq("in_progress")
      expect(batch.submitted_at).to be_present
      expect(batch.started_at).to be_present
      expect(batch.request_counts).to eq("submittedRequestCount" => 2)

      [task1, task2].each do |t|
        expect(t.raif_model_completion.reload.started_at).to be_present
      end
    end

    it "tolerates a top-level state field (in case the API returns the un-wrapped shape)" do
      stub_request(:post, create_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_top_level",
          state: "JOB_STATE_PENDING",
          done: false
        }.to_json
      )

      llm.submit_batch!(batch)

      expect(batch.reload.provider_batch_id).to eq("op_top_level")
      expect(batch.status).to eq("in_progress")
    end

    it "falls back to status: submitted when the response has no recognizable state field" do
      stub_request(:post, create_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { name: "batches/op_no_state" }.to_json
      )

      llm.submit_batch!(batch)
      expect(batch.reload.status).to eq("submitted")
    end

    it "raises if a child completion has a blank batch_custom_id" do
      bad = batch.raif_model_completions.first
      bad.update_columns(batch_custom_id: nil)

      stub_request(:post, create_endpoint).to_return(status: 200, body: "{}")

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError)
    end

    it "raises (without making a network call) if the batch was already submitted" do
      batch.update!(status: "submitted", provider_batch_id: "op_already", submitted_at: 1.minute.ago)
      stub = stub_request(:post, create_endpoint)

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /not submittable/)
      expect(stub).not_to have_been_requested
    end

    it "raises (without making a network call) if the encoded body would exceed the 20MB inline limit" do
      stub = stub_request(:post, create_endpoint)

      stub_const("Raif::Concerns::Llms::Google::BatchInference::INLINE_BATCH_MAX_BYTES", 50)

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /inline batch limit/)
      expect(stub).not_to have_been_requested
    end
  end

  describe "#fetch_batch_status!" do
    let!(:running_batch) do
      FB.create(
        :raif_model_completion_batch_google,
        provider_batch_id: "op_def456",
        provider_response: { "operation_name" => "batches/op_def456" },
        status: "submitted",
        submitted_at: 1.minute.ago,
        started_at: 1.minute.ago
      )
    end

    let(:status_endpoint) { "#{base_url}/batches/op_def456" }

    it "maps JOB_STATE_RUNNING to in_progress and JOB_STATE_SUCCEEDED to ended, recording ended_at and caching the response payload" do
      stub_request(:get, status_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_def456",
          metadata: { state: "JOB_STATE_RUNNING", batchStats: { processingRequestCount: 1 } },
          done: false
        }.to_json
      )

      expect(llm.fetch_batch_status!(running_batch)).to eq("in_progress")
      reloaded = running_batch.reload
      expect(reloaded.status).to eq("in_progress")
      expect(reloaded.ended_at).to be_nil
      expect(reloaded.request_counts).to eq("processingRequestCount" => 1)

      stub_request(:get, status_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_def456",
          metadata: { state: "JOB_STATE_SUCCEEDED" },
          done: true,
          response: {
            inlinedResponses: {
              inlinedResponses: [
                { metadata: { key: "x" }, response: { candidates: [], usageMetadata: {} } }
              ]
            }
          }
        }.to_json
      )

      expect(llm.fetch_batch_status!(running_batch)).to eq("ended")
      reloaded = running_batch.reload
      expect(reloaded.status).to eq("ended")
      expect(reloaded.ended_at).to be_present
      expect(reloaded.latest_response_payload).to be_present
      expect(reloaded.latest_response_payload.dig("inlinedResponses", "inlinedResponses").length).to eq(1)
    end

    it "maps the BATCH_STATE_* prefix the same way (the live generativelanguage.googleapis.com endpoint uses BATCH_STATE_*, not JOB_STATE_*)" do
      stub_request(:get, status_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_def456",
          metadata: { state: "BATCH_STATE_PENDING" },
          done: false
        }.to_json
      )

      expect(Raif.logger).not_to receive(:warn)
      expect(llm.fetch_batch_status!(running_batch)).to eq("in_progress")

      stub_request(:get, status_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_def456",
          metadata: { state: "BATCH_STATE_SUCCEEDED" },
          done: true,
          response: { inlinedResponses: { inlinedResponses: [] } }
        }.to_json
      )

      expect(llm.fetch_batch_status!(running_batch)).to eq("ended")
    end

    it "logs a warning for an unknown state and treats it as in_progress" do
      stub_request(:get, status_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_def456",
          metadata: { state: "JOB_STATE_PARTIALLY_BAKED" },
          done: false
        }.to_json
      )

      expect(Raif.logger).to receive(:warn).with(a_string_matching(/unknown Gemini batch state "JOB_STATE_PARTIALLY_BAKED"/))
      expect(llm.fetch_batch_status!(running_batch)).to eq("in_progress")
    end

    it "leaves an already-terminal batch alone even if the provider reports a non-terminal state (race guard)" do
      running_batch.update!(status: "failed", failed_at: Time.current, failure_reason: "max_age exceeded")

      stub_request(:get, status_endpoint).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          name: "batches/op_def456",
          metadata: { state: "JOB_STATE_RUNNING" },
          done: false
        }.to_json
      )

      expect(llm.fetch_batch_status!(running_batch)).to eq("failed")
      expect(running_batch.reload.status).to eq("failed")
    end
  end

  describe "#cancel_batch!" do
    let!(:running_batch) do
      FB.create(
        :raif_model_completion_batch_google,
        provider_batch_id: "op_cancel",
        provider_response: { "operation_name" => "batches/op_cancel" },
        status: "in_progress",
        submitted_at: 1.minute.ago,
        started_at: 1.minute.ago
      )
    end

    it "POSTs to {operation_name}:cancel and marks the batch in_progress while waiting for the next poll to confirm" do
      stub = stub_request(:post, "#{base_url}/batches/op_cancel:cancel")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "{}")

      expect(llm.cancel_batch!(running_batch)).to eq("in_progress")
      expect(stub).to have_been_requested
      expect(running_batch.reload.status).to eq("in_progress")
    end

    it "raises if the batch has no provider_batch_id (not yet submitted)" do
      pending_batch = FB.create(:raif_model_completion_batch_google, status: "pending")
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
        llm_model_key: "google_gemini_2_5_flash"
      )
    end

    let!(:task_failure) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "lose",
        creator: creator,
        llm_model_key: "google_gemini_2_5_flash"
      )
    end

    let(:cached_payload) do
      {
        "inlinedResponses" => {
          "inlinedResponses" => [
            {
              "metadata" => { "key" => "win" },
              "response" => {
                "candidates" => [
                  { "content" => { "parts" => [{ "text" => "Why did the chicken cross the road?" }] } }
                ],
                "usageMetadata" => {
                  "promptTokenCount" => 17,
                  "candidatesTokenCount" => 12,
                  "totalTokenCount" => 29
                }
              }
            },
            {
              "metadata" => { "key" => "lose" },
              "error" => { "code" => 400, "message" => "Sample failure for batch test" }
            }
          ]
        }
      }
    end

    before do
      batch.update!(
        provider_batch_id: "op_xyz",
        status: "ended",
        provider_response: batch.provider_response.merge(
          "operation_name" => "batches/op_xyz",
          "response" => cached_payload
        )
      )
    end

    it "walks inlinedResponses from the cached payload, populates the success completion, fails the error one, " \
      "applies the 50% discount, and recalculates batch costs" do
      llm.fetch_batch_results!(batch)

      win_mc = task_success.raif_model_completion.reload
      expect(win_mc.completed?).to be(true)
      expect(win_mc.raw_response).to eq("Why did the chicken cross the road?")
      expect(win_mc.prompt_tokens).to eq(17)
      expect(win_mc.completion_tokens).to eq(12)
      expect(win_mc.total_tokens).to eq(29)

      llm_config = Raif.llm_config(:google_gemini_2_5_flash)
      expected_prompt_cost = (llm_config[:input_token_cost] * 17) * 0.5
      expected_output_cost = (llm_config[:output_token_cost] * 12) * 0.5
      expect(win_mc.prompt_token_cost.to_f).to be_within(1e-6).of(expected_prompt_cost.to_f)
      expect(win_mc.output_token_cost.to_f).to be_within(1e-6).of(expected_output_cost.to_f)
      expect(win_mc.total_cost.to_f).to be_within(1e-6).of((expected_prompt_cost + expected_output_cost).to_f)

      no_discount_total = (llm_config[:input_token_cost] * 17) + (llm_config[:output_token_cost] * 12)
      expect(win_mc.total_cost.to_f).to be < no_discount_total.to_f

      lose_mc = task_failure.raif_model_completion.reload
      expect(lose_mc.failed?).to be(true)
      expect(lose_mc.failure_error).to include("code: 400")
      expect(lose_mc.failure_reason).to include("Sample failure")

      batch.reload
      expect(batch.total_cost.to_f).to be_within(1e-9).of(win_mc.total_cost.to_f)
    end

    it "fetches the operation directly when the cached response payload is missing" do
      batch.update!(provider_response: batch.provider_response.except("response"))

      stub_request(:get, "#{base_url}/batches/op_xyz")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            name: "batches/op_xyz",
            metadata: { state: "JOB_STATE_SUCCEEDED" },
            done: true,
            response: cached_payload
          }.to_json
        )

      llm.fetch_batch_results!(batch)

      expect(task_success.raif_model_completion.reload.completed?).to be(true)
      expect(task_failure.raif_model_completion.reload.failed?).to be(true)
    end

    it "logs and skips an unmatched key without raising, then force-fails any unmatched children" do
      batch.update!(
        provider_response: batch.provider_response.merge(
          "response" => {
            "inlinedResponses" => {
              "inlinedResponses" => [
                {
                  "metadata" => { "key" => "ghost" },
                  "response" => { "candidates" => [], "usageMetadata" => {} }
                }
              ]
            }
          }
        )
      )

      allow(Raif.logger).to receive(:warn)
      expect { llm.fetch_batch_results!(batch) }.not_to raise_error
      expect(Raif.logger).to have_received(:warn).with(a_string_matching(/did not match/))

      [task_success, task_failure].each do |t|
        mc = t.raif_model_completion.reload
        expect(mc.failed?).to be(true)
        expect(mc.failure_error).to include("missing")
        expect(mc.failure_reason).to include("not present in inlinedResponses")
      end
    end

    it "fails any child completion that doesn't appear in the inline results" do
      partial_payload = {
        "inlinedResponses" => {
          "inlinedResponses" => [
            {
              "metadata" => { "key" => "win" },
              "response" => {
                "candidates" => [{ "content" => { "parts" => [{ "text" => "ok" }] } }],
                "usageMetadata" => { "promptTokenCount" => 1, "candidatesTokenCount" => 1, "totalTokenCount" => 2 }
              }
            }
          ]
        }
      }
      batch.update!(provider_response: batch.provider_response.merge("response" => partial_payload))

      llm.fetch_batch_results!(batch)

      lose_mc = task_failure.raif_model_completion.reload
      expect(lose_mc.failed?).to be(true)
      expect(lose_mc.failure_error).to include("missing")
      expect(lose_mc.failure_reason).to include("not present in inlinedResponses")
    end

    it "tolerates a flat (un-doubled) inlinedResponses array shape" do
      flat_payload = {
        "inlinedResponses" => [
          {
            "metadata" => { "key" => "win" },
            "response" => {
              "candidates" => [{ "content" => { "parts" => [{ "text" => "ok" }] } }],
              "usageMetadata" => { "promptTokenCount" => 1, "candidatesTokenCount" => 1, "totalTokenCount" => 2 }
            }
          },
          {
            "metadata" => { "key" => "lose" },
            "error" => { "code" => 500, "message" => "boom" }
          }
        ]
      }
      batch.update!(provider_response: batch.provider_response.merge("response" => flat_payload))

      llm.fetch_batch_results!(batch)

      expect(task_success.raif_model_completion.reload.completed?).to be(true)
      expect(task_failure.raif_model_completion.reload.failed?).to be(true)
    end
  end
end
