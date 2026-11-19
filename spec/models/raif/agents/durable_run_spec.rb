# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Durable agent runs", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:creator) { FB.create(:raif_test_user) }
  let(:tools) { [Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool] }
  let(:agent) do
    Raif::DurableRunTestAgent.new(
      creator: creator,
      task: "Answer the question",
      max_iterations: 5,
      available_model_tools: tools,
      llm_model_key: "open_ai_responses_gpt_4_1"
    )
  end

  let(:model_calls) { [] }

  def tool_call(name, query, id)
    { "provider_tool_call_id" => id, "name" => name, "arguments" => { "query" => query } }
  end

  def final_answer_call(answer = "Done.")
    { "provider_tool_call_id" => "call_final", "name" => "agent_final_answer", "arguments" => { "final_answer" => answer } }
  end

  # The model answers each request with the next scripted batch of tool calls.
  def script_model(*batches)
    calls = model_calls
    stub_raif_agent(Raif::DurableRunTestAgent) do |messages, model_completion|
      calls << messages
      model_completion.response_tool_calls = batches[calls.length - 1] || [final_answer_call]
      "Thinking about step #{calls.length}."
    end
  end

  def enqueued(job_class)
    enqueued_jobs.select { |job| job["job_class"] == job_class.name }
  end

  def perform_jobs(job_class)
    perform_enqueued_jobs(only: job_class)
  end

  # Performs turn jobs and tool jobs until none are left. Deadline jobs stay queued.
  def drain_jobs
    20.times do
      break if enqueued(Raif::AgentTurnJob).empty? && enqueued(Raif::ModelToolInvocationJob).empty?

      perform_enqueued_jobs(only: [Raif::AgentTurnJob, Raif::ModelToolInvocationJob])
    end
  end

  def history_types(agent)
    agent.reload.conversation_history.map { |entry| entry["type"] || entry["role"] }
  end

  describe "#run_later!" do
    it "runs one job per turn and one job per tool call, and records results in call order" do
      script_model(
        [tool_call("durable_run_test_tool", "first", "call_1"), tool_call("durable_run_second_test_tool", "second", "call_2")]
      )

      expect(agent.run_later!).to eq(agent)
      expect(agent.status).to eq(:running)
      expect(enqueued(Raif::AgentTurnJob).length).to eq(1)
      expect(model_calls).to be_empty

      perform_jobs(Raif::AgentTurnJob)

      expect(agent.reload.status).to eq(:waiting)
      expect(agent.pending_tool_invocations.map(&:position)).to eq([0, 1])
      expect(enqueued(Raif::ModelToolInvocationJob).length).to eq(2)
      # Nothing is in the history until the barrier opens.
      expect(history_types(agent)).to eq(["user"])

      drain_jobs

      expect(agent.reload.status).to eq(:completed)
      expect(agent.final_answer).to eq("Done.")
      expect(model_calls.length).to eq(2)
      expect(history_types(agent)).to eq(["user", "tool_call", "tool_call_result", "tool_call", "tool_call_result", "tool_call"])
      expect(agent.conversation_history[1]["assistant_message"]).to eq("Thinking about step 1.")
      expect(agent.conversation_history[3]).not_to have_key("assistant_message")
      expect(agent.turns.pluck(:iteration, :status)).to eq([[1, "completed"], [2, "completed"]])
      expect(agent.iteration_count).to eq(2)
    end

    it "sends the model each result paired with its own call, whatever order the calls ended in" do
      script_model(
        [tool_call("durable_run_test_tool", "first", "call_1"), tool_call("durable_run_second_test_tool", "second", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)

      first, second = agent.raif_model_tool_invocations.in_call_order.to_a
      second.execute!
      expect(enqueued(Raif::AgentTurnJob)).to be_empty
      first.execute!

      # The barrier opened once and queued exactly one next turn.
      expect(enqueued(Raif::AgentTurnJob).length).to eq(1)
      expect(second.reload.completed_at).to be < first.reload.completed_at

      results = agent.reload.conversation_history.select { |entry| entry["type"] == "tool_call_result" }
      expect(results.map { |entry| entry["provider_tool_call_id"] }).to eq(["call_1", "call_2"])
      expect(results.map { |entry| entry["invocation_id"] }).to eq([first.id, second.id])

      drain_jobs
      replayed = model_calls.last.to_json
      expect(replayed).to match(/call_1.*result for first.*call_2.*result for second/m)
    end

    it "runs a single tool call in the turn job without a tool job" do
      script_model([tool_call("durable_run_test_tool", "only", "call_1")])
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)

      expect(enqueued(Raif::ModelToolInvocationJob)).to be_empty
      expect(Raif::DurableRunTestTool.executions.length).to eq(1)
      # The turn finished in its own job and queued the next one.
      expect(agent.turns.pluck(:status)).to eq(["completed", "pending"])
      expect(enqueued(Raif::AgentTurnJob).length).to eq(1)
    end

    it "restores the run context around tool code in jobs" do
      seen = []
      Raif::DurableRunTestTool.behavior { seen << Thread.current[:raif_durable_run_context] }
      Raif::DurableRunSecondTestTool.behavior { seen << Thread.current[:raif_durable_run_context] }
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")],
        [tool_call("durable_run_test_tool", "c", "call_3")]
      )
      agent.run_later!
      drain_jobs

      expect(seen).to eq(["agent-#{agent.id}"] * 3)
      expect(Thread.current[:raif_durable_run_context]).to be_nil
    end

    it "restores the run context around history hooks when a tool job opens the barrier" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      drain_jobs

      # The user entry is added by run_later! in the caller, which has its own context.
      contexts = Raif::DurableRunTestAgent.history_contexts
      expect(contexts.length).to eq(6)
      expect(contexts.drop(1).uniq).to eq(["agent-#{agent.id}"])
      expect(Thread.current[:raif_durable_run_context]).to be_nil
    end

    it "reports progress through the overridable hooks" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      drain_jobs

      expect(Raif::DurableRunTestAgent.events).to eq([
        [:entry, "user"],
        [:dispatched, 1],
        [:entry, "tool_call"],
        [:entry, "tool_call_result"],
        [:entry, "tool_call"],
        [:entry, "tool_call_result"],
        [:turn, 1],
        [:dispatched, 2],
        [:entry, "tool_call"],
        [:turn, 2],
        [:run, :completed]
      ])
    end

    it "commits the started run and its first turn together" do
      script_model
      agent.save!
      allow(agent).to receive(:open_turn!).and_raise(ActiveRecord::StatementInvalid, "connection lost")

      expect { agent.run_later! }.to raise_error(ActiveRecord::StatementInvalid)

      expect(Raif::Agent.find(agent.id).started_at).to be_nil
      expect(agent.turns).to be_empty
    end

    [1, 2].each do |call_count|
      it "keeps the run going when after_turn raises after a turn with #{call_count} tool call(s)" do
        allow_any_instance_of(Raif::DurableRunTestAgent).to receive(:after_turn).and_raise("hook broke")
        allow(Rails.error).to receive(:report)
        calls = [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
        script_model(calls.first(call_count))
        agent.run_later!

        perform_jobs(Raif::AgentTurnJob)
        perform_jobs(Raif::ModelToolInvocationJob) if call_count > 1

        expect(agent.reload.status).to eq(:running)
        expect(agent.current_turn.iteration).to eq(2)
        expect(enqueued(Raif::AgentTurnJob).length).to eq(1)
        expect(Rails.error).to have_received(:report).with(
          an_object_having_attributes(message: "hook broke"),
          hash_including(context: hash_including(action: "after_turn"))
        )

        drain_jobs
        expect(agent.reload).to be_completed
      end
    end

    it "refuses to start a run a second time" do
      script_model
      agent.run_later!

      expect { agent.run_later! }.to raise_error(Raif::Errors::AgentRunError, /already started/)
      expect { agent.run! }.to raise_error(Raif::Errors::AgentRunError, /already started/)
    end
  end

  describe "#run!" do
    it "performs the same steps in process and queues no turn or tool jobs" do
      script_model(
        [tool_call("durable_run_test_tool", "first", "call_1"), tool_call("durable_run_second_test_tool", "second", "call_2")]
      )

      yielded = []
      expect(agent.run! { |entry| yielded << (entry["type"] || entry["role"]) }).to eq("Done.")

      expect(enqueued_jobs).to be_empty
      expect(agent).to be_completed
      expect(agent.run_mode).to eq("in_process")
      expect(yielded).to eq(history_types(agent))
      expect(agent.raif_model_tool_invocations.where.not(deadline_at: nil)).to be_empty
    end

    it "raises before any model call when a tool defers completion" do
      script_model
      agent.available_model_tools = [Raif::DurableRunTestTool, Raif::DurableRunDeferredTestTool]

      expect { agent.run! }.to raise_error(Raif::Errors::AgentRunError, /durable_run_deferred_test_tool.*run_later!/)
      expect(model_calls).to be_empty
      expect(agent).not_to be_persisted
    end

    it "raises for a deferred tool that only populate_default_model_tools adds, and saves nothing" do
      agent = Raif::DurableRunDefaultDeferredToolAgent.new(
        creator: creator,
        task: "Answer the question",
        llm_model_key: "open_ai_responses_gpt_4_1"
      )

      expect { agent.run! }.to raise_error(Raif::Errors::AgentRunError, /durable_run_deferred_test_tool.*run_later!/)
      expect(agent).not_to be_persisted
      expect(Raif::Agent.where(type: "Raif::DurableRunDefaultDeferredToolAgent")).to be_empty
    end
  end

  describe "agent classes that implement process_iteration_model_completion" do
    let(:hook_agent) do
      Raif::DurableRunHookAgent.new(creator: creator, task: "Answer the question", llm_model_key: "open_ai_responses_gpt_4_1")
    end

    before do
      stub_raif_agent(Raif::DurableRunHookAgent) { "The answer." }
    end

    it "runs the hook outside the agent's lock under run!" do
      outside = Raif::Agent.connection.open_transactions

      expect(hook_agent.run!).to eq("The answer.")
      expect(Raif::DurableRunHookAgent.open_transactions_in_hook).to eq([outside])
    end

    it "runs the hook outside the agent's lock under run_later!" do
      outside = Raif::Agent.connection.open_transactions

      hook_agent.run_later!
      drain_jobs

      expect(hook_agent.reload).to be_completed
      expect(hook_agent.final_answer).to eq("The answer.")
      expect(Raif::DurableRunHookAgent.open_transactions_in_hook).to eq([outside])
    end

    it "calls the history callback after the start commits under run!" do
      outside = Raif::Agent.connection.open_transactions

      hook_agent.run!

      expect(Raif::DurableRunHookAgent.open_transactions_in_history_callback).to all(eq(outside))
      expect(Raif::DurableRunHookAgent.open_transactions_in_history_callback.length).to eq(2)
    end

    it "calls the history callback after the start commits under run_later!" do
      outside = Raif::Agent.connection.open_transactions

      hook_agent.run_later!

      expect(Raif::DurableRunHookAgent.open_transactions_in_history_callback).to eq([outside])
    end

    it "adds the hook's entries once when the hook runs again after the process stops" do
      Raif::DurableRunHookAgent.hook_failures_left = 1
      hook_agent.run_later!
      turn = hook_agent.current_turn

      stopped = Raif::Agent.find(hook_agent.id)
      stopped.hold_run_token(stopped.run_token)
      expect { stopped.perform_turn!(turn) }.to raise_error(/stopped after adding its entry/)
      expect(turn.reload).to be_completion_saved

      drain_jobs

      expect(hook_agent.reload).to be_completed
      expect(hook_agent.conversation_history.count { |entry| entry["role"] == "assistant" }).to eq(1)
    end
  end

  describe "job retries" do
    it "does not call the model again when a turn job runs twice" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      turn = agent.current_turn

      2.times { Raif::AgentTurnJob.perform_now(agent: Raif::Agent.find(agent.id), turn_id: turn.id, run_token: agent.run_token) }

      expect(model_calls.length).to eq(1)
      expect(agent.raif_model_tool_invocations.count).to eq(2)
    end

    it "attaches a completion that was saved before the turn recorded it" do
      script_model
      agent.run_later!
      turn = agent.current_turn
      turn.update!(started_at: 1.minute.ago)
      saved = FB.create(
        :raif_model_completion,
        source: agent,
        llm_model_key: agent.llm_model_key,
        model_api_name: "gpt-4.1",
        response_format: "text",
        started_at: 30.seconds.ago,
        completed_at: 20.seconds.ago,
        response_tool_calls: [final_answer_call("From the saved completion.")]
      )

      drain_jobs

      expect(model_calls).to be_empty
      expect(turn.reload.raif_model_completion).to eq(saved)
      expect(agent.reload.final_answer).to eq("From the saved completion.")
    end

    it "does not run a tool again when its job is delivered twice" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      invocation = agent.raif_model_tool_invocations.in_call_order.first

      2.times { Raif::ModelToolInvocationJob.perform_now(model_tool_invocation: Raif::ModelToolInvocation.find(invocation.id)) }

      expect(Raif::DurableRunTestTool.executions).to eq([invocation.id])
    end

    it "never runs a tool a second time for an invocation whose first execution was abandoned" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      invocation = agent.raif_model_tool_invocations.in_call_order.first
      # A worker claimed the invocation and stopped before the tool returned.
      invocation.update_columns(started_at: 1.hour.ago, execution_token: "gone", lease_expires_at: 50.minutes.ago)

      expect(invocation.execute!).to be(false)
      expect(Raif::DurableRunTestTool.executions).to be_empty
      expect(invocation.reload).not_to be_finished
    end

    it "lets a retry_safe tool take over an abandoned invocation once the lease expired" do
      agent.available_model_tools = [Raif::DurableRunRetrySafeTestTool, Raif::DurableRunSecondTestTool]
      script_model(
        [tool_call("durable_run_retry_safe_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      invocation = agent.raif_model_tool_invocations.in_call_order.first

      invocation.update_columns(started_at: 30.seconds.ago, execution_token: "gone", lease_expires_at: 90.seconds.from_now)
      expect(invocation.execute!).to be(false)

      invocation.update_columns(lease_expires_at: 1.second.ago)
      expect(invocation.execute!).to be(true)
      expect(Raif::DurableRunRetrySafeTestTool.executions).to eq([invocation.id])
      expect(invocation.reload).to be_completed
    end
  end

  describe "fencing" do
    it "ignores a turn job that carries an old run token" do
      script_model
      agent.run_later!
      turn = agent.current_turn

      Raif::AgentTurnJob.perform_now(agent: agent, turn_id: turn.id, run_token: "stale")

      expect(model_calls).to be_empty
      expect(turn.reload).to be_pending
    end

    it "stops a waiting run on cancel! and ignores work that arrives later" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      old_token = agent.reload.run_token

      expect(agent.cancel!).to be(true)
      expect(agent.status).to eq(:canceled)
      expect(agent.run_token).not_to eq(old_token)
      expect(agent.cancel!).to be(false)

      drain_jobs

      expect(Raif::DurableRunTestTool.executions).to be_empty
      expect(agent.raif_model_tool_invocations.pluck(:canceled_at)).to all(be_present)
      expect(model_calls.length).to eq(1)
      expect(history_types(agent)).to eq(["user"])
      expect(agent.resume!).to be(false)
    end
  end

  describe "tool errors in jobs" do
    it "gives the model an error result for a recoverable error and continues" do
      Raif::DurableRunTestTool.behavior { raise StandardError, "secret internal detail" }
      allow(Rails.error).to receive(:report)
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      drain_jobs

      expect(agent.reload).to be_completed
      error_entry = agent.conversation_history[2]
      expect(error_entry).to include("type" => "tool_call_result", "tool_error" => true, "provider_tool_call_id" => "call_1")
      expect(error_entry["result"]).to include("durable_run_test_tool tool failed")
      expect(error_entry["result"]).not_to include("secret")
      expect(agent.conversation_history[4]).to include("provider_tool_call_id" => "call_2", "result" => { "answer" => "result for b" })
    end

    it "fails the run on an error the model cannot work around, and a later sibling result does not revive it" do
      Raif::DurableRunTestTool.behavior do
        raise StandardError.new("over budget").extend(Raif::Errors::ModelCompletionAuthorizationError)
      end
      allow(Rails.error).to receive(:report)
      script_model(
        [
          tool_call("durable_run_test_tool", "a", "call_1"),
          tool_call("durable_run_second_test_tool", "b", "call_2"),
          tool_call("durable_run_second_test_tool", "c", "call_3")
        ]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      failing, running, queued = agent.raif_model_tool_invocations.in_call_order.to_a

      # The second call is already running when the first one fails.
      running.update_columns(started_at: Time.current, execution_token: "running", lease_expires_at: 5.minutes.from_now)
      failing.execute!

      expect(agent.reload.status).to eq(:failed)
      expect(agent.failure_reason).to eq("over budget")
      expect(queued.reload).to be_canceled
      expect(running.reload).not_to be_finished

      # The queued sibling does not start, and the running one cannot advance the run.
      expect(queued.execute!).to be(false)
      running.send(:finish!, execution_token: "running")
      expect(running.barrier_owner.check_tool_barrier!).to be(false)

      drain_jobs
      expect(Raif::DurableRunSecondTestTool.executions).to be_empty
      expect(model_calls.length).to eq(1)
      expect(agent.reload.status).to eq(:failed)
      expect(Raif::DurableRunTestAgent.events.last).to eq([:run, :failed])
    end

    it "does not fail the run for a fatal error from an execution whose invocation already ended" do
      Raif::DurableRunTestTool.behavior do |invocation|
        # The deadline passes while the tool runs.
        Raif::ModelToolInvocation.where(id: invocation.id).update_all(failed_at: Time.current, failure_reason: "deadline")
        raise StandardError.new("over budget").extend(Raif::Errors::ModelCompletionAuthorizationError)
      end
      allow(Rails.error).to receive(:report)
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      late, sibling = agent.raif_model_tool_invocations.in_call_order.to_a

      expect(late.execute!).to be(true)
      expect(late.reload.failure_reason).to eq("deadline")
      expect(agent.reload.status).to eq(:waiting)

      expect(sibling.execute!).to be(true)
      drain_jobs
      expect(agent.reload).to be_completed
    end

    it "fails the run when the model call raises in a turn job" do
      allow(Rails.error).to receive(:report)
      stub_raif_agent(Raif::DurableRunTestAgent) { |_messages, _completion| raise Faraday::ClientError, "bad request" }
      agent.run_later!

      expect { drain_jobs }.not_to raise_error
      expect(agent.reload.status).to eq(:failed)
      expect(agent.failure_reason).to eq("bad request")
    end
  end

  describe "deferred completion" do
    let(:tools) { [Raif::DurableRunTestTool, Raif::DurableRunDeferredTestTool] }

    def start_deferred_run(*first_batch)
      first_batch = [tool_call("durable_run_deferred_test_tool", "slow", "call_slow")] if first_batch.empty?
      script_model(first_batch)
      agent.run_later!
      drain_jobs
      agent.raif_model_tool_invocations.find_by!(tool_type: "Raif::DurableRunDeferredTestTool")
    end

    it "waits without a model call until the host completes the invocation" do
      invocation = start_deferred_run

      expect(Raif::DurableRunDeferredTestTool.executions).to eq([invocation.id])
      expect(invocation).to be_deferred_completion
      expect(invocation.deadline_at).to be_within(5.seconds).of(45.minutes.from_now)
      expect(agent.reload.status).to eq(:waiting)
      expect(agent.pending_tool_invocations).to eq([invocation])
      expect(enqueued(Raif::AgentTurnJob)).to be_empty
      expect(model_calls.length).to eq(1)
      expect(agent.iteration_count).to eq(1)

      expect(invocation.complete!("rows" => [1, 2])).to be(true)
      expect(enqueued(Raif::AgentTurnJob).length).to eq(1)
      drain_jobs

      expect(agent.reload).to be_completed
      expect(agent.iteration_count).to eq(2)
      expect(agent.conversation_history[2]).to include("type" => "tool_call_result", "result" => { "rows" => [1, 2] })
      # A second completion changes nothing.
      expect(invocation.complete!("rows" => [])).to be(false)
      expect(invocation.reload.result).to eq("rows" => [1, 2])
    end

    it "waits for the deferred call while a sibling call finishes" do
      invocation = start_deferred_run(
        tool_call("durable_run_test_tool", "fast", "call_fast"),
        tool_call("durable_run_deferred_test_tool", "slow", "call_slow")
      )

      expect(Raif::DurableRunTestTool.executions.length).to eq(1)
      expect(agent.reload.status).to eq(:waiting)
      expect(agent.pending_tool_invocations).to eq([invocation])

      invocation.complete!("ok" => true)
      drain_jobs

      expect(agent.reload).to be_completed
      results = agent.conversation_history.select { |entry| entry["type"] == "tool_call_result" }
      expect(results.map { |entry| entry["provider_tool_call_id"] }).to eq(["call_fast", "call_slow"])
    end

    it "gives the model the host's message when the host fails the invocation" do
      invocation = start_deferred_run

      expect(invocation.fail!("The upstream source returned no data for that query.")).to be(true)
      drain_jobs

      expect(agent.reload).to be_completed
      expect(agent.conversation_history[2]).to include(
        "tool_error" => true,
        "result" => "The upstream source returned no data for that query."
      )
    end

    it "gives the model an error result when the deadline passes, and ignores a late completion" do
      invocation = start_deferred_run
      expect(enqueued(Raif::ModelToolInvocationDeadlineJob).length).to eq(1)

      # Before the deadline the job does nothing.
      Raif::ModelToolInvocationDeadlineJob.perform_now(model_tool_invocation: invocation)
      expect(invocation.reload).not_to be_finished

      travel_to(46.minutes.from_now) do
        Raif::ModelToolInvocationDeadlineJob.perform_now(model_tool_invocation: invocation)
        expect(invocation.reload).to be_failed
        drain_jobs

        expect(agent.reload).to be_completed
        expect(agent.conversation_history[2]["tool_error"]).to be(true)
        expect(agent.conversation_history[2]["result"]).to include("did not return a result before its deadline")
        expect(invocation.complete!("late" => true)).to be(false)
        expect(invocation.reload.result).to eq({})
      end
    end

    it "does not run a retry_safe deferred tool again while it waits for the host" do
      agent.available_model_tools = [Raif::DurableRunTestTool, Raif::DurableRunRetrySafeDeferredTestTool]
      script_model([tool_call("durable_run_retry_safe_deferred_test_tool", "slow", "call_slow")])
      agent.run_later!
      drain_jobs
      invocation = agent.raif_model_tool_invocations.sole
      expect(invocation.lease_expires_at).to be_nil

      travel_to(10.minutes.from_now) do
        expect(agent.resume!).to be(true)
        drain_jobs
        Raif::ModelToolInvocationJob.perform_now(model_tool_invocation: invocation)
      end

      expect(Raif::DurableRunRetrySafeDeferredTestTool.executions).to eq([invocation.id])
      expect(invocation.reload).not_to be_finished
    end

    it "does not expire an invocation from a stale deadline after extend_deadline! committed" do
      invocation = start_deferred_run
      stale = Raif::ModelToolInvocation.find(invocation.id)
      invocation.extend_deadline!(2.hours.from_now)

      travel_to(46.minutes.from_now) do
        expect(stale.expire!).to be(false)
        expect(invocation.reload).not_to be_finished
      end
    end

    it "moves the deadline with extend_deadline!" do
      invocation = start_deferred_run
      invocation.extend_deadline!(2.hours.from_now)

      travel_to(46.minutes.from_now) do
        Raif::ModelToolInvocationDeadlineJob.perform_now(model_tool_invocation: invocation)
        expect(invocation.reload).not_to be_finished
      end
    end
  end

  describe "recovery" do
    it "resumes a turn whose job was lost" do
      script_model
      agent.run_later!
      clear_enqueued_jobs

      expect(agent.resume!).to be(true)
      drain_jobs

      expect(agent.reload).to be_completed
    end

    it "dispatches tool calls again when their jobs were never queued" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      clear_enqueued_jobs

      agent.resume!
      drain_jobs

      expect(agent.reload).to be_completed
      expect(Raif::DurableRunTestTool.executions.length).to eq(1)
      expect(Raif::DurableRunSecondTestTool.executions.length).to eq(1)
    end

    it "opens the barrier when every invocation ended but the check never ran" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      clear_enqueued_jobs
      agent.raif_model_tool_invocations.update_all(started_at: Time.current, completed_at: Time.current, result: { "answer" => "x" })

      agent.resume!
      drain_jobs

      expect(agent.reload).to be_completed
      expect(Raif::DurableRunTestTool.executions).to be_empty
    end

    it "runs a continuation that was lost after the barrier opened" do
      script_model(
        [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
      )
      agent.run_later!
      perform_jobs(Raif::AgentTurnJob)
      turn = agent.current_turn
      allow_any_instance_of(Raif::AgentTurn).to receive(:continue_after_tools!)
      perform_jobs(Raif::ModelToolInvocationJob)
      expect(turn.reload).to be_tools_complete
      expect(enqueued(Raif::AgentTurnJob)).to be_empty

      agent.resume!
      drain_jobs

      expect(agent.reload).to be_completed
      expect(agent.turns.pluck(:status)).to eq(["completed", "completed"])
      expect(history_types(agent).count("tool_call_result")).to eq(2)
    end

    describe Raif::RecoverStalledRunsJob do
      it "resumes async runs that stopped changing, and leaves in-process and recent runs alone" do
        script_model
        agent.run_later!
        clear_enqueued_jobs

        described_class.perform_now
        expect(enqueued(Raif::AgentTurnJob)).to be_empty

        agent.current_turn.update_columns(updated_at: 31.minutes.ago)
        in_process = Raif::DurableRunTestAgent.create!(
          creator: creator, task: "t", available_model_tools: tools, llm_model_key: agent.llm_model_key,
          started_at: 1.hour.ago, run_mode: "in_process", run_token: "x"
        )
        in_process.turns.create!(iteration: 1).update_columns(updated_at: 31.minutes.ago)

        described_class.perform_now

        jobs = enqueued(Raif::AgentTurnJob)
        expect(jobs.length).to eq(1)
        drain_jobs
        expect(agent.reload).to be_completed
      end

      it "does not resume runs when agent_stalled_turn_resume_after is nil" do
        allow(Raif.config).to receive(:agent_stalled_turn_resume_after).and_return(nil)
        script_model
        agent.run_later!
        clear_enqueued_jobs
        agent.current_turn.update_columns(updated_at: 2.hours.ago)

        described_class.perform_now

        expect(enqueued(Raif::AgentTurnJob)).to be_empty
      end

      it "expires overdue invocations whose deadline job never ran, and continues past a failing record" do
        agent.available_model_tools = [Raif::DurableRunTestTool, Raif::DurableRunDeferredTestTool]
        script_model([tool_call("durable_run_deferred_test_tool", "slow", "call_slow")])
        agent.run_later!
        drain_jobs
        clear_enqueued_jobs
        invocation = agent.raif_model_tool_invocations.first
        broken = FB.create(:raif_model_tool_invocation, source: agent, deadline_at: 2.hours.ago)
        allow(Rails.error).to receive(:report)
        allow_any_instance_of(Raif::ModelToolInvocation).to receive(:expire!).and_wrap_original do |original, *args, **kwargs|
          raise "boom" if original.receiver.id == broken.id

          original.call(*args, **kwargs)
        end

        travel_to(46.minutes.from_now) do
          allow(Raif.config).to receive(:agent_stalled_turn_resume_after).and_return(nil)
          described_class.perform_now

          expect(invocation.reload).to be_failed
          expect(Rails.error).to have_received(:report).with(an_instance_of(RuntimeError), hash_including(handled: true))
          drain_jobs
          expect(agent.reload).to be_completed
        end
      end
    end
  end
end
