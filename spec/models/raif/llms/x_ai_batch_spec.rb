# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::XAi, "batch inference" do
  let(:creator) { FB.build(:raif_test_user) }
  let(:base_url) { "https://api.x.ai/v1" }
  let(:llm) { Raif.llm(:x_ai_grok_4_3) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
  end

  describe ".supports_batch_inference?" do
    it "is true" do
      expect(Raif::Llms::XAi.supports_batch_inference?).to be(true)
    end
  end

  describe "#batch_class" do
    it "returns Raif::ModelCompletionBatches::XAi" do
      expect(llm.batch_class).to eq(Raif::ModelCompletionBatches::XAi)
    end
  end

  describe "#submit_batch!" do
    let(:batch) do
      FB.create(
        :raif_model_completion_batch_x_ai,
        llm_model_key: "x_ai_grok_4_3",
        model_api_name: "grok-4.3"
      )
    end

    let!(:task1) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "task_a",
        creator: creator,
        llm_model_key: "x_ai_grok_4_3"
      )
    end

    let!(:task2) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "task_b",
        creator: creator,
        llm_model_key: "x_ai_grok_4_3"
      )
    end

    it "uploads a JSONL input file then creates a batch referencing the file id" do
      files_stub = stub_request(:post, "#{base_url}/files")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { id: "file_xai_1" }.to_json
        )

      create_stub = stub_request(:post, "#{base_url}/batches")
        .with(body: hash_including("name" => "raif_batch_#{batch.id}", "input_file_id" => "file_xai_1"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            batch_id: "batch_xai_1",
            expires_at: 1.day.from_now.iso8601,
            state: { num_requests: 2, num_pending: 2 }
          }.to_json
        )

      llm.submit_batch!(batch)

      expect(files_stub).to have_been_requested
      expect(create_stub).to have_been_requested

      files_signature = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.find do |sig|
        sig.uri.to_s.end_with?("/files") && sig.method == :post
      end
      expect(files_signature).to be_present
      expect(files_signature.headers["Content-Type"]).to include("multipart/form-data")

      # Decode the multipart body's `file` part and assert each JSONL line targets
      # /v1/chat/completions with the unchanged sync-path body shape (messages,
      # not the Responses-API `input`). The original bug was wrapping the body
      # under `responses` with `messages`, which xAI rejects with 422.
      multipart_body = files_signature.body.to_s
      expect(multipart_body).to include('name="file"')
      expect(multipart_body).to include('filename="batch.jsonl"')

      jsonl_payload = multipart_body[/Content-Disposition: form-data; name="file".*?\r\n\r\n(.+?)\r\n--/m, 1]
      expect(jsonl_payload).to be_present

      lines = jsonl_payload.strip.lines.map(&:strip).reject(&:empty?)
      expect(lines.size).to eq(2)

      entries = lines.map { |l| JSON.parse(l) }
      expect(entries.map { |e| e["custom_id"] }).to contain_exactly("task_a", "task_b")
      entries.each do |entry|
        expect(entry["method"]).to eq("POST")
        expect(entry["url"]).to eq("/v1/chat/completions")
        body_json = entry["body"]
        expect(body_json["model"]).to eq("grok-4.3")
        expect(body_json["messages"]).to be_an(Array)
        expect(body_json).not_to have_key("stream")
        expect(body_json).not_to have_key("stream_options")
        expect(body_json).not_to have_key("input")
      end

      batch.reload
      expect(batch.provider_batch_id).to eq("batch_xai_1")
      expect(batch.status).to eq("submitted")
      expect(batch.submitted_at).to be_present
      expect(batch.started_at).to be_present
      expect(batch.expires_at).to be_present
      expect(batch.provider_response["input_file_id"]).to eq("file_xai_1")
      expect(batch.request_counts).to include("total" => 2, "pending" => 2)
    end

    it "raises without uploading or creating if the batch was already submitted" do
      batch.update!(status: "submitted", provider_batch_id: "batch_already_submitted", submitted_at: 1.minute.ago)
      files_stub = stub_request(:post, "#{base_url}/files")
      create_stub = stub_request(:post, "#{base_url}/batches")

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /not submittable/)
      expect(files_stub).not_to have_been_requested
      expect(create_stub).not_to have_been_requested
    end

    it "raises if any child completion has a blank batch_custom_id" do
      task1.raif_model_completion.update_column(:batch_custom_id, nil)

      files_stub = stub_request(:post, "#{base_url}/files")
      create_stub = stub_request(:post, "#{base_url}/batches")

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /blank batch_custom_id/)
      expect(files_stub).not_to have_been_requested
      expect(create_stub).not_to have_been_requested
    end

    it "raises if /v1/files returns no file id" do
      stub_request(:post, "#{base_url}/files").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {}.to_json
      )
      create_stub = stub_request(:post, "#{base_url}/batches")

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /no file id/)
      expect(create_stub).not_to have_been_requested
    end

    it "raises if /v1/batches returns no batch id" do
      stub_request(:post, "#{base_url}/files").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { id: "file_xai_no_batch" }.to_json
      )
      stub_request(:post, "#{base_url}/batches").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {}.to_json
      )

      expect { llm.submit_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /no batch id/)
    end
  end

  describe "#fetch_batch_status!" do
    let!(:batch) do
      FB.create(
        :raif_model_completion_batch_x_ai,
        provider_batch_id: "batch_status_target",
        status: "submitted",
        submitted_at: 1.minute.ago
      )
    end

    it "maps num_pending > 0 to in_progress" do
      stub_request(:get, "#{base_url}/batches/batch_status_target").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { batch_id: "batch_status_target", state: { num_requests: 2, num_pending: 1, num_success: 1 } }.to_json
      )
      expect(llm.fetch_batch_status!(batch)).to eq("in_progress")
      expect(batch.reload.status).to eq("in_progress")
    end

    it "maps num_pending == 0 with no cancellations to ended" do
      stub_request(:get, "#{base_url}/batches/batch_status_target").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          batch_id: "batch_status_target",
          state: { num_requests: 2, num_pending: 0, num_success: 2, num_error: 0, num_cancelled: 0 }
        }.to_json
      )
      expect(llm.fetch_batch_status!(batch)).to eq("ended")
      expect(batch.reload.ended_at).to be_present
    end

    it "maps num_pending == 0 with cancellations to canceled" do
      stub_request(:get, "#{base_url}/batches/batch_status_target").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          batch_id: "batch_status_target",
          state: { num_requests: 2, num_pending: 0, num_success: 1, num_error: 0, num_cancelled: 1 }
        }.to_json
      )
      expect(llm.fetch_batch_status!(batch)).to eq("canceled")
    end

    it "maps a past expires_at with pending entries to expired" do
      stub_request(:get, "#{base_url}/batches/batch_status_target").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          batch_id: "batch_status_target",
          state: { num_requests: 2, num_pending: 2, num_success: 0 },
          expires_at: 1.minute.ago.iso8601
        }.to_json
      )
      expect(llm.fetch_batch_status!(batch)).to eq("expired")
    end

    it "preserves previously-persisted request_counts when a poll body omits state" do
      batch.update!(request_counts: { "total" => 2, "pending" => 1, "success" => 1 })

      stub_request(:get, "#{base_url}/batches/batch_status_target").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { batch_id: "batch_status_target" }.to_json
      )

      llm.fetch_batch_status!(batch)

      expect(batch.reload.request_counts).to eq({ "total" => 2, "pending" => 1, "success" => 1 })
    end
  end

  describe "#cancel_batch!" do
    let!(:batch) do
      FB.create(
        :raif_model_completion_batch_x_ai,
        provider_batch_id: "batch_cancel_target",
        status: "in_progress",
        submitted_at: 1.minute.ago
      )
    end

    it "POSTs to /v1/batches/:id:cancel and reports the new status" do
      stub = stub_request(:post, "#{base_url}/batches/batch_cancel_target:cancel").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          batch_id: "batch_cancel_target",
          state: { num_requests: 2, num_pending: 1, num_success: 1, num_cancelled: 0 }
        }.to_json
      )

      expect(llm.cancel_batch!(batch)).to eq("in_progress")
      expect(stub).to have_been_requested
      expect(batch.reload.status).to eq("in_progress")
    end

    it "returns canceled once num_pending reaches 0" do
      stub_request(:post, "#{base_url}/batches/batch_cancel_target:cancel").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          batch_id: "batch_cancel_target",
          state: { num_requests: 2, num_pending: 0, num_success: 1, num_cancelled: 1 }
        }.to_json
      )
      expect(llm.cancel_batch!(batch)).to eq("canceled")
    end

    it "raises if the batch has no provider_batch_id" do
      pending_batch = FB.create(:raif_model_completion_batch_x_ai, status: "pending")
      expect { llm.cancel_batch!(pending_batch) }.to raise_error(Raif::Errors::InvalidBatchError, /no provider_batch_id/)
    end

    it "raises if the batch is already terminal" do
      batch.update!(status: "ended", ended_at: Time.current)
      expect { llm.cancel_batch!(batch) }.to raise_error(Raif::Errors::InvalidBatchError, /already terminal/)
    end
  end

  describe "#fetch_batch_results! / #apply_batch_result" do
    let(:batch) do
      FB.create(
        :raif_model_completion_batch_x_ai,
        llm_model_key: "x_ai_grok_4_3",
        model_api_name: "grok-4.3",
        provider_batch_id: "batch_results_target",
        status: "ended",
        started_at: 1.minute.ago
      )
    end

    let!(:task_success) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "ok_id",
        creator: creator,
        llm_model_key: "x_ai_grok_4_3"
      )
    end

    let!(:task_failure) do
      Raif::TestTask.build_for_batch(
        batch: batch,
        batch_custom_id: "bad_id",
        creator: creator,
        llm_model_key: "x_ai_grok_4_3"
      )
    end

    it "parses chat_get_completion success and error envelopes, applies the batch discount" do
      results_body = {
        results: [
          {
            batch_request_id: "ok_id",
            batch_result: {
              response: {
                chat_get_completion: {
                  id: "chatcmpl_ok",
                  choices: [{ message: { role: "assistant", content: "A successful joke." } }],
                  usage: { prompt_tokens: 11, completion_tokens: 7, total_tokens: 18 }
                }
              }
            }
          },
          {
            batch_request_id: "bad_id",
            batch_result: {
              error: { message: "Synthetic xAI batch failure" }
            }
          }
        ]
      }.to_json

      stub_request(:get, "#{base_url}/batches/batch_results_target/results")
        .to_return(status: 200, body: results_body, headers: { "Content-Type" => "application/json" })

      llm.fetch_batch_results!(batch)

      ok = task_success.raif_model_completion.reload
      expect(ok.completed?).to be(true)
      expect(ok.raw_response).to eq("A successful joke.")
      expect(ok.prompt_tokens).to eq(11)
      expect(ok.completion_tokens).to eq(7)

      llm_config = Raif.llm_config(:x_ai_grok_4_3)
      no_discount_total = (llm_config[:input_token_cost] * 11) + (llm_config[:output_token_cost] * 7)
      expect(ok.total_cost.to_f).to be < no_discount_total.to_f

      bad = task_failure.raif_model_completion.reload
      expect(bad.failed?).to be(true)
      expect(bad.failure_reason).to include("Synthetic xAI batch failure")
    end

    it "paginates through results when the first page returns a pagination_token" do
      first_page = {
        results: [
          {
            batch_request_id: "ok_id",
            batch_result: {
              response: {
                chat_get_completion: {
                  id: "chatcmpl_a",
                  choices: [{ message: { role: "assistant", content: "first" } }],
                  usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
                }
              }
            }
          }
        ],
        pagination_token: "page2"
      }.to_json

      second_page = {
        results: [
          {
            batch_request_id: "bad_id",
            batch_result: {
              response: {
                chat_get_completion: {
                  id: "chatcmpl_b",
                  choices: [{ message: { role: "assistant", content: "second" } }],
                  usage: { prompt_tokens: 2, completion_tokens: 2, total_tokens: 4 }
                }
              }
            }
          }
        ],
        pagination_token: nil
      }.to_json

      stub_request(:get, %r{#{Regexp.escape(base_url)}/batches/batch_results_target/results})
        .to_return(
          { status: 200, body: first_page, headers: { "Content-Type" => "application/json" } },
          { status: 200, body: second_page, headers: { "Content-Type" => "application/json" } }
        )

      llm.fetch_batch_results!(batch)

      expect(task_success.raif_model_completion.reload.raw_response).to eq("first")
      expect(task_failure.raif_model_completion.reload.raw_response).to eq("second")
    end

    it "force-fails child completions missing from the results stream" do
      results_body = {
        results: [{
          batch_request_id: "ok_id",
          batch_result: {
            response: {
              chat_get_completion: {
                id: "chatcmpl_ok",
                choices: [{ message: { role: "assistant", content: "ok" } }],
                usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
              }
            }
          }
        }],
        pagination_token: nil
      }.to_json

      stub_request(:get, "#{base_url}/batches/batch_results_target/results")
        .to_return(status: 200, body: results_body, headers: { "Content-Type" => "application/json" })

      llm.fetch_batch_results!(batch)

      missing = task_failure.raif_model_completion.reload
      expect(missing.failed?).to be(true)
      expect(missing.failure_error).to include("missing")
    end

    it "logs a warning and skips an unknown batch_request_id without raising" do
      results_body = {
        results: [
          {
            batch_request_id: "ghost",
            batch_result: { response: { chat_get_completion: { choices: [], usage: {} } } }
          },
          {
            batch_request_id: "ok_id",
            batch_result: {
              response: {
                chat_get_completion: {
                  id: "chatcmpl_x",
                  choices: [{ message: { role: "assistant", content: "matched" } }],
                  usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
                }
              }
            }
          }
        ]
      }.to_json

      stub_request(:get, "#{base_url}/batches/batch_results_target/results")
        .to_return(status: 200, body: results_body, headers: { "Content-Type" => "application/json" })

      allow(Raif.logger).to receive(:warn)
      expect { llm.fetch_batch_results!(batch) }.not_to raise_error
      expect(Raif.logger).to have_received(:warn).with(a_string_matching(/did not match/))
    end
  end
end
