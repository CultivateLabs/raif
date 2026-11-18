# frozen_string_literal: true

require "rails_helper"

# The barrier, the execution claim and the terminal writes are only correct if
# they hold when several database connections race. Transactional tests share
# one connection, so this group runs without them and cleans up after itself.
RSpec.describe "Durable agent run concurrency", type: :model do
  self.use_transactional_tests = false

  let(:creator) { FB.create(:raif_test_user) }
  let(:agent) do
    Raif::DurableRunTestAgent.create!(
      creator: creator,
      task: "Answer the question",
      available_model_tools: [Raif::DurableRunTestTool, Raif::DurableRunDeferredTestTool],
      llm_model_key: "open_ai_responses_gpt_4_1",
      started_at: Time.current,
      run_mode: "async",
      run_token: "token",
      iteration_count: 1,
      conversation_history: [{ "role" => "user", "content" => "Answer the question" }]
    )
  end
  let(:turn) { agent.turns.create!(iteration: 1, status: "tools_dispatched", started_at: Time.current) }

  after do
    Raif::ModelToolInvocation.delete_all
    Raif::AgentTurn.delete_all
    Raif::Agent.delete_all
    Raif::TestUser.delete_all
  end

  def create_invocation(position, tool: Raif::DurableRunTestTool, **attributes)
    tool.build_invocation(
      provider_tool_call_id: "call_#{position}",
      tool_arguments: { "query" => "q#{position}" },
      source: agent,
      raif_agent_turn: turn,
      position: position,
      **attributes
    ).tap(&:save!)
  end

  # Runs each block in its own thread and database connection, releasing them together.
  def race(*blocks)
    ready = Queue.new
    go = Queue.new

    threads = blocks.map do |block|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          block.call
        end
      end
    end

    blocks.length.times { ready.pop }
    blocks.length.times { go << true }
    threads.map(&:value)
  end

  def turn_jobs
    enqueued_jobs.select { |job| job["job_class"] == "Raif::AgentTurnJob" }
  end

  it "opens the barrier once when all tool calls of a turn end at the same moment" do
    invocations = Array.new(4) { |position| create_invocation(position) }

    race(*invocations.map { |invocation| -> { Raif::ModelToolInvocation.find(invocation.id).execute! } })

    expect(Raif::DurableRunTestTool.executions.sort).to eq(invocations.map(&:id).sort)
    expect(turn.reload).to be_completed
    expect(agent.turns.pluck(:iteration)).to eq([1, 2])
    expect(turn_jobs.length).to eq(1)

    results = agent.reload.conversation_history.select { |entry| entry["type"] == "tool_call_result" }
    expect(results.map { |entry| entry["provider_tool_call_id"] }).to eq(["call_0", "call_1", "call_2", "call_3"])
    expect(agent.conversation_history.length).to eq(9)
  end

  it "runs a tool once when the same invocation is executed concurrently" do
    invocation = create_invocation(0)
    create_invocation(1, tool: Raif::DurableRunDeferredTestTool, started_at: Time.current)

    outcomes = race(*Array.new(4) { -> { Raif::ModelToolInvocation.find(invocation.id).execute! } })

    expect(outcomes.count(true)).to eq(1)
    expect(Raif::DurableRunTestTool.executions).to eq([invocation.id])
    expect(invocation.reload).to be_completed
  end

  it "lets exactly one of a host completion and a deadline expiry end an invocation" do
    invocation = create_invocation(0, tool: Raif::DurableRunDeferredTestTool, started_at: 1.hour.ago, deadline_at: 1.minute.ago)

    outcomes = race(
      -> { Raif::ModelToolInvocation.find(invocation.id).complete!("rows" => [1]) },
      -> { Raif::ModelToolInvocation.find(invocation.id).expire! }
    )

    expect(outcomes.count(true)).to eq(1)
    invocation.reload
    expect([invocation.completed?, invocation.failed?].count(true)).to eq(1)
    expect(turn.reload).to be_completed
    expect(turn_jobs.length).to eq(1)
    expect(agent.reload.conversation_history.count { |entry| entry["type"] == "tool_call_result" }).to eq(1)
  end

  it "never advances a run that is canceled while its last tool call ends" do
    invocation = create_invocation(0)

    race(
      -> { Raif::ModelToolInvocation.find(invocation.id).execute! },
      -> { Raif::Agent.find(agent.id).cancel! }
    )

    expect(agent.reload.status).to eq(:canceled)
    statuses = agent.turns.pluck(:iteration, :status)

    # Whatever was queued before the cancel carries the old token and does nothing.
    perform_enqueued_jobs(only: [Raif::AgentTurnJob, Raif::ModelToolInvocationJob])

    expect(agent.turns.pluck(:iteration, :status)).to eq(statuses)
    expect(agent.raif_model_completions).to be_empty
    expect(agent.reload.status).to eq(:canceled)
  end
end
