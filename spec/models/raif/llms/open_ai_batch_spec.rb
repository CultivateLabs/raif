# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::OpenAiBase, "batch inference" do
  let(:creator) { FB.build(:raif_test_user) }
  let(:base_url) { Raif.config.open_ai_base_url }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
  end

  describe ".supports_batch_inference?" do
    it "is true for both OpenAiResponses and OpenAiCompletions" do
      expect(Raif::Llms::OpenAiResponses.supports_batch_inference?).to be(true)
      expect(Raif::Llms::OpenAiCompletions.supports_batch_inference?).to be(true)
    end
  end

  describe "#batch_class" do
    it "returns Raif::ModelCompletionBatches::OpenAi for both subclasses" do
      expect(Raif.llm(:open_ai_responses_gpt_4o).batch_class).to eq(Raif::ModelCompletionBatches::OpenAi)
      expect(Raif.llm(:open_ai_gpt_4o).batch_class).to eq(Raif::ModelCompletionBatches::OpenAi)
    end
  end

  describe "#batch_endpoint_path" do
    it "is /v1/responses for OpenAiResponses" do
      expect(Raif.llm(:open_ai_responses_gpt_4o).batch_endpoint_path).to eq("/v1/responses")
    end

    it "is /v1/chat/completions for OpenAiCompletions" do
      expect(Raif.llm(:open_ai_gpt_4o).batch_endpoint_path).to eq("/v1/chat/completions")
    end
  end

  describe "#submit_batch! (Responses)" do
    let(:llm) { Raif.llm(:open_ai_responses_gpt_4o) }
    let(:batch) do
      FB.create(
        :raif_model_completion_batch_open_ai_responses,
        llm_model_key: "open_ai_responses_gpt_4o",
        model_api_name: "gpt-4o"
      )
    end

    let!(:task1) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        custom_request_id: "task_a",
        creator: creator,
        llm_model_key: "open_ai_responses_gpt_4o"
      )
    end

    let!(:task2) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        custom_request_id: "task_b",
        creator: creator,
        llm_model_key: "open_ai_responses_gpt_4o"
      )
    end

    it "uploads JSONL via /v1/files then creates the batch with input_file_id and the right endpoint" do
      file_upload_stub = stub_request(:post, "#{base_url}/files").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { id: "file-input-abc", object: "file", purpose: "batch" }.to_json
      )

      batch_create_stub = stub_request(:post, "#{base_url}/batches")
        .with(body: hash_including(
          "input_file_id" => "file-input-abc",
          "endpoint" => "/v1/responses",
          "completion_window" => "24h"
        ))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            id: "batch_abc",
            status: "in_progress",
            request_counts: { total: 2, completed: 0, failed: 0 }
          }.to_json
        )

      llm.submit_batch!(batch)

      expect(file_upload_stub).to have_been_requested
      expect(batch_create_stub).to have_been_requested

      # Inspect the multipart body of the file upload to verify each JSONL
      # line has custom_id + url + body, and that body matches build_request_parameters.
      upload_signature = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find do |sig|
        sig.uri.to_s.end_with?("/files") && sig.method == :post
      end
      expect(upload_signature).to be_present

      # The multipart body contains the JSONL content as one of its parts.
      multipart_body = upload_signature.body
      expect(multipart_body).to include('name="purpose"')
      expect(multipart_body).to include("batch")
      expect(multipart_body).to include('name="file"')
      expect(multipart_body).to include('filename="batch.jsonl"')

      jsonl_section = multipart_body[/Content-Type: application\/jsonl\s*\r?\n\r?\n(.+?)(?=\r?\n----)/m, 1]
      expect(jsonl_section).to be_present

      lines = jsonl_section.strip.lines.map(&:strip).reject(&:blank?)
      expect(lines.size).to eq(2)
      parsed = lines.map { |l| JSON.parse(l) }
      expect(parsed.map { |p| p["custom_id"] }).to contain_exactly("task_a", "task_b")
      parsed.each do |entry|
        expect(entry["method"]).to eq("POST")
        expect(entry["url"]).to eq("/v1/responses")
        expect(entry["body"]["model"]).to eq("gpt-4o")
        expect(entry["body"]["input"]).to eq([
          { "role" => "user", "content" => [{ "type" => "input_text", "text" => "Tell me a joke" }] }
        ])
      end

      batch.reload
      expect(batch.provider_batch_id).to eq("batch_abc")
      expect(batch.status).to eq("in_progress")
      expect(batch.input_file_id).to eq("file-input-abc")
      expect(batch.endpoint).to eq("/v1/responses")
    end
  end

  describe "#fetch_batch_status!" do
    let(:llm) { Raif.llm(:open_ai_responses_gpt_4o) }
    let!(:batch) do
      FB.create(
        :raif_model_completion_batch_open_ai_responses,
        provider_batch_id: "batch_zzz",
        status: "submitted",
        submitted_at: 1.minute.ago
      )
    end

    it "maps in_progress -> in_progress and completed -> ended, recording output_file_id" do
      stub_request(:get, "#{base_url}/batches/batch_zzz").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: "batch_zzz",
          status: "in_progress",
          request_counts: { total: 1, completed: 0, failed: 0 }
        }.to_json
      )
      expect(llm.fetch_batch_status!(batch)).to eq("in_progress")
      expect(batch.reload.status).to eq("in_progress")

      stub_request(:get, "#{base_url}/batches/batch_zzz").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: "batch_zzz",
          status: "completed",
          request_counts: { total: 1, completed: 1, failed: 0 },
          output_file_id: "file-output-zzz",
          error_file_id: nil
        }.to_json
      )
      expect(llm.fetch_batch_status!(batch)).to eq("ended")
      reloaded = batch.reload
      expect(reloaded.status).to eq("ended")
      expect(reloaded.output_file_id).to eq("file-output-zzz")
      expect(reloaded.ended_at).to be_present
    end

    it "maps cancelled -> canceled and expired -> expired" do
      stub_request(:get, "#{base_url}/batches/batch_zzz").to_return(
        status: 200,
        body: { id: "batch_zzz", status: "cancelled", request_counts: {} }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      expect(llm.fetch_batch_status!(batch)).to eq("canceled")

      stub_request(:get, "#{base_url}/batches/batch_zzz").to_return(
        status: 200,
        body: { id: "batch_zzz", status: "expired", request_counts: {} }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      expect(llm.fetch_batch_status!(batch)).to eq("expired")
    end
  end

  describe "#fetch_batch_results! / #apply_batch_result (Responses)" do
    let(:llm) { Raif.llm(:open_ai_responses_gpt_4o) }
    let(:batch) do
      FB.create(
        :raif_model_completion_batch_open_ai_responses,
        llm_model_key: "open_ai_responses_gpt_4o",
        model_api_name: "gpt-4o",
        provider_batch_id: "batch_results_test",
        status: "ended",
        started_at: 1.minute.ago,
        provider_response: {
          "input_file_id" => "file-in",
          "output_file_id" => "file-out",
          "endpoint" => "/v1/responses"
        }
      )
    end

    let!(:task_success) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        custom_request_id: "ok_id",
        creator: creator,
        llm_model_key: "open_ai_responses_gpt_4o"
      )
    end

    let!(:task_failure) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        custom_request_id: "bad_id",
        creator: creator,
        llm_model_key: "open_ai_responses_gpt_4o"
      )
    end

    let(:output_jsonl) do
      [
        {
          id: "batch_req_1",
          custom_id: "ok_id",
          response: {
            status_code: 200,
            request_id: "req_a",
            body: {
              id: "resp_abc",
              output: [{
                type: "message",
                content: [{ type: "output_text", text: "A successful joke." }]
              }],
              usage: { input_tokens: 11, output_tokens: 7, total_tokens: 18 }
            }
          },
          error: nil
        },
        {
          id: "batch_req_2",
          custom_id: "bad_id",
          response: {
            status_code: 400,
            request_id: "req_b",
            body: { error: { message: "Sample 400 from batch test" } }
          },
          error: nil
        }
      ].map(&:to_json).join("\n")
    end

    it "downloads the output file, applies the discount on success, marks failure entries failed" do
      stub_request(:get, "#{base_url}/files/file-out/content").to_return(status: 200, body: output_jsonl)

      llm.fetch_batch_results!(batch)

      ok = task_success.raif_model_completion.reload
      expect(ok.completed?).to be(true)
      expect(ok.raw_response).to eq("A successful joke.")
      expect(ok.prompt_tokens).to eq(11)
      expect(ok.completion_tokens).to eq(7)

      llm_config = Raif.llm_config(:open_ai_responses_gpt_4o)
      no_discount_total = (llm_config[:input_token_cost] * 11) + (llm_config[:output_token_cost] * 7)
      expect(ok.total_cost.to_f).to be < no_discount_total.to_f

      bad = task_failure.raif_model_completion.reload
      expect(bad.failed?).to be(true)
      expect(bad.failure_reason).to include("Sample 400")
    end

    it "fails any child completion that doesn't appear in the output_file or error_file" do
      stub_request(:get, "#{base_url}/files/file-out/content").to_return(
        status: 200,
        body: { id: "x", custom_id: "ok_id", response: { status_code: 200, body: { output: [], usage: {} } } }.to_json
      )

      llm.fetch_batch_results!(batch)

      missing = task_failure.raif_model_completion.reload
      expect(missing.failed?).to be(true)
      expect(missing.failure_error).to include("missing")
    end

    it "logs and skips an unknown custom_id without raising" do
      stub_request(:get, "#{base_url}/files/file-out/content").to_return(
        status: 200,
        body: [
          { id: "x", custom_id: "ghost", response: { status_code: 200, body: { output: [], usage: {} } } }.to_json,
          { id: "y", custom_id: "ok_id", response: { status_code: 200, body: { output: [], usage: {} } } }.to_json
        ].join("\n")
      )

      expect(Raif.logger).to receive(:warn).with(a_string_matching(/did not match/))
      expect { llm.fetch_batch_results!(batch) }.not_to raise_error
    end
  end

  describe "JSONL body shape (Completions)" do
    let(:llm) { Raif.llm(:open_ai_gpt_4o) }
    let(:batch) do
      FB.create(
        :raif_model_completion_batch_open_ai_completions,
        llm_model_key: "open_ai_gpt_4o",
        model_api_name: "gpt-4o"
      )
    end

    let!(:task) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        custom_request_id: "comp_a",
        creator: creator,
        llm_model_key: "open_ai_gpt_4o"
      )
    end

    it "uses /v1/chat/completions as the per-line url and embeds chat_completions request shape" do
      stub_request(:post, "#{base_url}/files").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { id: "file-comp-in" }.to_json
      )
      stub_request(:post, "#{base_url}/batches")
        .with(body: hash_including("endpoint" => "/v1/chat/completions"))
        .to_return(status: 200, body: { id: "batch_comp_abc", status: "in_progress" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      llm.submit_batch!(batch)

      upload_signature = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find do |sig|
        sig.uri.to_s.end_with?("/files") && sig.method == :post
      end
      jsonl = upload_signature.body[/Content-Type: application\/jsonl\s*\r?\n\r?\n(.+?)(?=\r?\n----)/m, 1].to_s.strip

      parsed = JSON.parse(jsonl.lines.first.strip)
      expect(parsed["url"]).to eq("/v1/chat/completions")
      # chat/completions uses messages, not input
      expect(parsed["body"]["messages"]).to be_an(Array)
      expect(parsed["body"]).not_to have_key("input")
    end
  end
end
