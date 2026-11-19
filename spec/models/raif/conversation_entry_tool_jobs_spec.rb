# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation entry tool jobs", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:creator) { FB.create(:raif_test_user) }
  let(:conversation) { Raif::DurableRunTestConversation.create!(creator: creator) }
  let(:entry) { conversation.entries.create!(creator: creator, user_message: "Look these up", started_at: Time.current) }
  let(:model_calls) { [] }

  def tool_call(name, query, id)
    { "provider_tool_call_id" => id, "name" => name, "arguments" => { "query" => query } }
  end

  # The model answers each request with the next scripted batch of tool calls.
  def script_model(*batches)
    calls = model_calls
    stub_raif_conversation(Raif::DurableRunTestConversation) do |messages, model_completion|
      calls << messages
      model_completion.response_tool_calls = batches[calls.length - 1] || []
      "Response #{calls.length}"
    end
  end

  def enqueued(job_class)
    enqueued_jobs.select { |job| job["job_class"] == job_class.name }
  end

  def perform_tool_jobs
    perform_enqueued_jobs(only: Raif::ModelToolInvocationJob)
  end

  let(:two_calls) do
    [tool_call("durable_run_test_tool", "first", "call_1"), tool_call("durable_run_second_test_tool", "second", "call_2")]
  end

  it "completes an entry without tool calls in the entry job, as before" do
    script_model
    entry.process_entry!

    expect(entry.reload).to be_completed
    expect(entry.tools_dispatched_at).to be_nil
    expect(enqueued(Raif::ModelToolInvocationJob)).to be_empty
    expect(Raif::DurableRunTestConversation.finalized_entry_ids).to eq([entry.id])
  end

  it "runs a single tool call in the entry job and completes the entry" do
    seen = []
    Raif::DurableRunTestTool.behavior { seen << Thread.current[:raif_durable_run_context] }
    script_model([tool_call("durable_run_test_tool", "only", "call_1")])
    entry.process_entry!

    expect(enqueued(Raif::ModelToolInvocationJob)).to be_empty
    expect(seen).to eq(["entry-#{entry.id}"])
    expect(entry.reload).to be_completed
    expect(entry.finalized_at).to be_present
    expect(conversation.reload.generating_entry_response).to be(false)
    expect(Raif::DurableRunTestConversation.finalized_entry_ids).to eq([entry.id])
  end

  it "runs several tool calls as jobs and holds the entry until the last one ends" do
    seen = []
    Raif::DurableRunTestTool.behavior { seen << Thread.current[:raif_durable_run_context] }
    script_model(two_calls)
    entry.process_entry!

    expect(entry.reload).to be_waiting_on_tools
    expect(entry).to be_generating_response
    expect(entry.model_response_message).to eq("Response 1")
    expect(entry.pending_tool_invocations.map(&:position)).to eq([0, 1])
    expect(conversation.reload.generating_entry_response).to be(true)
    expect(enqueued(Raif::ModelToolInvocationJob).length).to eq(2)
    expect(Raif::DurableRunTestConversation.finalized_entry_ids).to be_empty

    first, second = entry.raif_model_tool_invocations.in_call_order.to_a
    second.execute!
    expect(entry.reload).not_to be_completed
    first.execute!

    expect(entry.reload).to be_completed
    expect(entry).not_to be_waiting_on_tools
    expect(seen).to eq(["entry-#{entry.id}"])
    expect(Raif::DurableRunTestConversation.finalized_contexts).to eq(["entry-#{entry.id}"])
    expect(conversation.reload.generating_entry_response).to be(false)
    expect(Raif::DurableRunTestConversation.finalized_entry_ids).to eq([entry.id])

    # Results reach the model in call order, although the second call ended first.
    results = conversation.llm_messages.select { |message| message["type"] == "tool_call_result" }
    expect(results.map { |message| message["provider_tool_call_id"] }).to eq(["call_1", "call_2"])
  end

  it "fails the entry when a tool raises and cancels calls that did not start" do
    Raif::DurableRunTestTool.behavior { raise "tool exploded" }
    allow(Rails.error).to receive(:report)
    script_model(two_calls)
    entry.process_entry!
    first, second = entry.raif_model_tool_invocations.in_call_order.to_a

    first.execute!

    expect(entry.reload).to be_failed
    expect(entry).not_to be_completed
    expect(second.reload).to be_canceled
    expect(conversation.reload.generating_entry_response).to be(false)

    perform_tool_jobs
    expect(Raif::DurableRunSecondTestTool.executions).to be_empty
    expect(Raif::DurableRunTestConversation.finalized_entry_ids).to be_empty
    expect(conversation.llm_messages.select { |message| message["type"] == "tool_call" }).to be_empty
  end

  it "fails the entry and clears the generating flag when dispatching the tool calls raises" do
    allow_any_instance_of(Raif::ModelToolInvocation).to receive(:schedule_deadline_job).and_raise("queue down")
    script_model(two_calls)
    entry.process_entry!

    expect(entry.reload).to be_failed
    expect(conversation.reload.generating_entry_response).to be(false)
  end

  it "does not fail the entry for an error from an execution that lost its claim" do
    Raif::DurableRunTestTool.behavior do |invocation|
      # Another execution takes the call over while this one runs.
      Raif::ModelToolInvocation.where(id: invocation.id).update_all(execution_token: "taken over")
      raise "tool exploded"
    end
    allow(Rails.error).to receive(:report)
    script_model(two_calls)
    entry.process_entry!
    first = entry.raif_model_tool_invocations.in_call_order.first

    expect(first.execute!).to be(true)

    expect(entry.reload).not_to be_failed
    expect(first.reload).not_to be_finished
    expect(Rails.error).to have_received(:report).with(an_object_having_attributes(message: "tool exploded"), anything)
  end

  describe "deferred completion" do
    let(:deferred_call) { [tool_call("durable_run_deferred_test_tool", "slow", "call_slow")] }

    it "waits for the host and then prompts the model again only when the tool asks for it" do
      script_model(deferred_call)
      entry.process_entry!
      invocation = entry.raif_model_tool_invocations.first

      expect(entry.reload).to be_waiting_on_tools
      expect(model_calls.length).to eq(1)

      expect(invocation.complete!("rows" => [1])).to be(true)

      expect(entry.reload).to be_completed
      expect(Raif::DurableRunTestConversation.finalized_entry_ids).to eq([entry.id])
      expect(conversation.entries.count).to eq(1)
      expect(invocation.complete!("rows" => [2])).to be(false)
    end

    it "completes the entry with an error result when the deadline passes, and prompts the model again" do
      script_model(deferred_call)
      entry.process_entry!
      invocation = entry.raif_model_tool_invocations.first

      travel_to(46.minutes.from_now) do
        Raif::ModelToolInvocationDeadlineJob.perform_now(model_tool_invocation: invocation)

        expect(entry.reload).to be_completed
        expect(conversation.entries.count).to eq(2)
        result = conversation.llm_messages.find { |message| message["type"] == "tool_call_result" }
        expect(result["result"]).to include("did not return a result before its deadline")
      end
    end

    it "queues the follow-up entry job only after the host's transaction commits" do
      script_model(deferred_call)
      entry.process_entry!
      clear_enqueued_jobs

      ActiveRecord::Base.transaction do
        entry.raif_model_tool_invocations.first.fail!("No data for that query.")
        expect(enqueued(Raif::ConversationEntryJob)).to be_empty
      end

      expect(enqueued(Raif::ConversationEntryJob).length).to eq(1)
    end

    it "sends the host's message to the model when the host fails the call" do
      script_model(deferred_call)
      entry.process_entry!

      entry.raif_model_tool_invocations.first.fail!("No data for that query.")

      expect(entry.reload).to be_completed
      result = conversation.llm_messages.find { |message| message["type"] == "tool_call_result" }
      expect(result["result"]).to eq("No data for that query.")
      expect(conversation.entries.count).to eq(2)
    end
  end

  it "queues a job for a lost single call instead of running the tool in the recovery sweep" do
    script_model([tool_call("durable_run_test_tool", "only", "call_1")])
    allow_any_instance_of(Raif::ConversationEntry).to receive(:run_tool_invocations!)
    entry.process_entry!
    allow_any_instance_of(Raif::ConversationEntry).to receive(:run_tool_invocations!).and_call_original
    expect(entry.reload).to be_waiting_on_tools

    entry.update_columns(updated_at: 31.minutes.ago)
    Raif::RecoverStalledRunsJob.perform_now

    expect(Raif::DurableRunTestTool.executions).to be_empty
    expect(enqueued(Raif::ModelToolInvocationJob).length).to eq(1)
    perform_tool_jobs
    expect(entry.reload).to be_completed
  end

  describe "recovery" do
    before do
      script_model(two_calls)
      entry.process_entry!
    end

    def sweep
      entry.update_columns(updated_at: 31.minutes.ago)
      Raif::RecoverStalledRunsJob.perform_now
    end

    it "queues tool jobs again when they were lost" do
      clear_enqueued_jobs

      sweep
      perform_tool_jobs

      expect(entry.reload).to be_completed
      expect(Raif::DurableRunTestTool.executions.length).to eq(1)
    end

    it "runs a continuation that was lost after the entry completed" do
      allow_any_instance_of(Raif::ConversationEntry).to receive(:continue_after_tools!)
      perform_tool_jobs
      expect(entry.reload).to be_completed
      expect(entry.finalized_at).to be_nil
      expect(Raif::DurableRunTestConversation.finalized_entry_ids).to be_empty
      allow_any_instance_of(Raif::ConversationEntry).to receive(:continue_after_tools!).and_call_original

      sweep

      expect(entry.reload.finalized_at).to be_present
      expect(Raif::DurableRunTestConversation.finalized_entry_ids).to eq([entry.id])
      expect(conversation.reload.generating_entry_response).to be(false)

      # A finalized entry is left alone.
      sweep
      expect(Raif::DurableRunTestConversation.finalized_entry_ids).to eq([entry.id])
    end

    it "leaves a recently changed entry alone" do
      clear_enqueued_jobs
      Raif::RecoverStalledRunsJob.perform_now

      expect(enqueued(Raif::ModelToolInvocationJob)).to be_empty
    end
  end
end
