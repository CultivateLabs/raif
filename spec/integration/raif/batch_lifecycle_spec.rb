# frozen_string_literal: true

require "rails_helper"

# End-to-end exercise of the batch primitive's seam:
#
#   Task.build_for_batch (x N)
#   -> batch.submit! (auto-enqueues PollModelCompletionBatchJob)
#   -> poll attempt 1 (provider says in_progress, reschedules)
#   -> poll attempt 2 (provider says ended, fetches results, dispatches handler)
#   -> Raif::TaskBatchCompletionHandler routes per-entry results back to source tasks
#
# Each individual seam has its own focused spec; this spec exists to catch
# wiring regressions across the whole chain.
RSpec.describe "Batch lifecycle", type: :model do
  let(:creator) { FB.build(:raif_test_user) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
  end

  it "drives a batch from submit through poll, finalize, handler dispatch, and per-task completion" do
    llm = Raif.llm(:anthropic_claude_4_5_haiku)
    batch = Raif::ModelCompletionBatches::Anthropic.create!(
      llm_model_key: "anthropic_claude_4_5_haiku",
      model_api_name: llm.api_name,
      completion_handler_class_name: "Raif::TaskBatchCompletionHandler"
    )

    success_task = Raif::TestTask.build_for_batch(
      batch: batch,
      batch_custom_id: "win",
      creator: creator,
      llm_model_key: "anthropic_claude_4_5_haiku"
    )

    fail_task = Raif::TestTask.build_for_batch(
      batch: batch,
      batch_custom_id: "lose",
      creator: creator,
      llm_model_key: "anthropic_claude_4_5_haiku"
    )

    # Provider stubs:
    submit_stub = stub_request(:post, "https://api.anthropic.com/v1/messages/batches")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        id: "msgbatch_e2e",
        processing_status: "in_progress",
        request_counts: { processing: 2, succeeded: 0, errored: 0, canceled: 0, expired: 0 }
      }.to_json)

    results_url = "https://api.anthropic.com/v1/messages/batches/msgbatch_e2e/results"

    in_progress_response = {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        id: "msgbatch_e2e",
        processing_status: "in_progress",
        request_counts: { processing: 2, succeeded: 0, errored: 0, canceled: 0, expired: 0 }
      }.to_json
    }
    ended_response = {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        id: "msgbatch_e2e",
        processing_status: "ended",
        request_counts: { processing: 0, succeeded: 1, errored: 1, canceled: 0, expired: 0 },
        results_url: results_url
      }.to_json
    }
    stub_request(:get, "https://api.anthropic.com/v1/messages/batches/msgbatch_e2e")
      .to_return(in_progress_response, ended_response)

    jsonl_body = [
      {
        custom_id: "win",
        result: {
          type: "succeeded",
          message: {
            id: "msg_win",
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "joke!" }],
            usage: { input_tokens: 5, output_tokens: 3, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
          }
        }
      },
      {
        custom_id: "lose",
        result: { type: "errored", error: { type: "invalid_request_error", message: "bad" } }
      }
    ].map(&:to_json).join("\n")
    stub_request(:get, results_url).to_return(status: 200, body: jsonl_body)

    # 1. submit! posts to provider and auto-enqueues the first poll
    expect do
      batch.submit!
    end.to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(batch.id)

    expect(submit_stub).to have_been_requested
    expect(batch.reload.provider_batch_id).to eq("msgbatch_e2e")
    expect(batch.status).to eq("in_progress")
    expect(batch.next_poll_at).to be_present

    # 2. First poll: provider still in_progress -> reschedule
    expect do
      Raif::PollModelCompletionBatchJob.new.perform(batch.id, attempt: 1)
    end.to have_enqueued_job(Raif::PollModelCompletionBatchJob).with(batch.id, attempt: 2)

    expect(batch.reload.status).to eq("in_progress")
    expect(success_task.reload.status).to eq(:pending)
    expect(fail_task.reload.status).to eq(:pending)

    # 3. Second poll: provider returns ended -> fetch results -> dispatch handler
    expect do
      Raif::PollModelCompletionBatchJob.new.perform(batch.id, attempt: 2)
    end.not_to have_enqueued_job(Raif::PollModelCompletionBatchJob)

    # 4. Final state: batch terminal, tasks routed correctly through the handler
    batch.reload
    expect(batch.status).to eq("ended")
    expect(batch).to be_terminal
    expect(batch).to be_successful

    success_task.reload
    expect(success_task.status).to eq(:completed)
    expect(success_task.raw_response).to eq("joke!")
    expect(success_task.raif_model_completion).to be_completed
    expect(success_task.raif_model_completion.prompt_tokens).to eq(5)
    expect(success_task.raif_model_completion.completion_tokens).to eq(3)

    fail_task.reload
    expect(fail_task.status).to eq(:failed)
    expect(fail_task.raif_model_completion).to be_failed
    expect(fail_task.raif_model_completion.failure_reason).to include("bad")

    # 5. Batch-level cost rollup picked up the (50% discounted) success entry
    expect(batch.total_cost.to_f).to be > 0
  end
end
