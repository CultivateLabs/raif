# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Raif.config.model_tool_invocation_authorizer", type: :model do
  let(:creator) { FB.create(:raif_test_user) }
  let(:authorized) { [] }
  let(:vetoed_tool) { nil }

  before do
    seen = authorized
    vetoed = vetoed_tool
    authorizer = lambda do |invocation:|
      seen << [invocation.tool, invocation.source.class.base_class, Thread.current[:raif_durable_run_context]]
      raise ArgumentError, "#{invocation.tool_name} is not allowed" if invocation.tool == vetoed
    end
    allow(Raif.config).to receive(:model_tool_invocation_authorizer).and_return(authorizer)
    allow(Rails.error).to receive(:report)
  end

  def tool_call(name, query, id)
    { "provider_tool_call_id" => id, "name" => name, "arguments" => { "query" => query } }
  end

  def final_answer_call
    { "provider_tool_call_id" => "call_final", "name" => "agent_final_answer", "arguments" => { "final_answer" => "Done." } }
  end

  def script(stub_method, klass, *batches)
    calls = 0
    public_send(stub_method, klass) do |_messages, model_completion|
      calls += 1
      model_completion.response_tool_calls = batches[calls - 1] || (stub_method == :stub_raif_agent ? [final_answer_call] : [])
      "Step #{calls}"
    end
  end

  def new_agent(tools, **attributes)
    Raif::DurableRunTestAgent.new(
      creator: creator,
      task: "Answer the question",
      max_iterations: 5,
      available_model_tools: tools,
      llm_model_key: "open_ai_responses_gpt_4_1",
      **attributes
    )
  end

  let(:two_calls) do
    [tool_call("durable_run_test_tool", "a", "call_1"), tool_call("durable_run_second_test_tool", "b", "call_2")]
  end

  describe "the single entry point" do
    it "authorizes agent tool calls that run in tool jobs, inside the run context" do
      agent = new_agent([Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool])
      script(:stub_raif_agent, Raif::DurableRunTestAgent, two_calls)
      agent.run_later!
      perform_raif_run_jobs

      expect(agent.reload).to be_completed
      expect(authorized).to contain_exactly(
        [Raif::DurableRunTestTool, Raif::Agent, "agent-#{agent.id}"],
        [Raif::DurableRunSecondTestTool, Raif::Agent, "agent-#{agent.id}"],
        [Raif::ModelTools::AgentFinalAnswer, Raif::Agent, "agent-#{agent.id}"]
      )
    end

    it "authorizes agent tool calls in an in-process run" do
      agent = new_agent([Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool])
      script(:stub_raif_agent, Raif::DurableRunTestAgent, two_calls)
      agent.run!

      expect(authorized.map(&:first)).to eq([Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool, Raif::ModelTools::AgentFinalAnswer])
    end

    it "authorizes a tool that defers completion when its work starts" do
      agent = new_agent([Raif::DurableRunTestTool, Raif::DurableRunDeferredTestTool])
      script(:stub_raif_agent, Raif::DurableRunTestAgent, [tool_call("durable_run_deferred_test_tool", "slow", "call_slow")])
      agent.run_later!
      perform_raif_run_jobs

      expect(agent.reload.status).to eq(:waiting)
      expect(authorized.map(&:first)).to eq([Raif::DurableRunDeferredTestTool])
    end

    it "authorizes conversation tool calls, in the entry job and in tool jobs" do
      conversation = Raif::DurableRunTestConversation.create!(creator: creator)
      script(:stub_raif_conversation, Raif::DurableRunTestConversation, [tool_call("durable_run_test_tool", "only", "call_0")], two_calls)

      first = conversation.entries.create!(creator: creator, user_message: "One call", started_at: Time.current)
      first.process_entry!
      expect(first.reload).to be_completed

      second = conversation.entries.create!(creator: creator, user_message: "Two calls", started_at: Time.current)
      second.process_entry!
      perform_raif_run_jobs
      expect(second.reload).to be_completed

      expect(authorized).to contain_exactly(
        [Raif::DurableRunTestTool, Raif::ConversationEntry, "entry-#{first.id}"],
        [Raif::DurableRunTestTool, Raif::ConversationEntry, "entry-#{second.id}"],
        [Raif::DurableRunSecondTestTool, Raif::ConversationEntry, "entry-#{second.id}"]
      )
    end

    it "authorizes Raif::ModelTool.invoke_tool" do
      agent = FB.create(:raif_native_tool_calling_agent, creator: creator)
      invocation = Raif::DurableRunTestTool.invoke_tool(provider_tool_call_id: "call_1", tool_arguments: { "query" => "a" }, source: agent)

      expect(invocation).to be_completed
      expect(authorized.map(&:first)).to eq([Raif::DurableRunTestTool])
    end
  end

  describe "a veto" do
    let(:vetoed_tool) { Raif::DurableRunTestTool }

    it "fails an agent run in jobs without running the tool, and cancels calls that did not start" do
      agent = new_agent([Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool])
      script(:stub_raif_agent, Raif::DurableRunTestAgent, two_calls)
      agent.run_later!
      perform_enqueued_jobs(only: Raif::AgentTurnJob)
      vetoed, sibling = agent.raif_model_tool_invocations.in_call_order.to_a

      vetoed.execute!

      expect(Raif::DurableRunTestTool.executions).to be_empty
      expect(agent.reload.status).to eq(:failed)
      expect(agent.failure_reason).to eq("durable_run_test_tool is not allowed")
      expect(vetoed.reload).to be_failed
      expect(sibling.reload).to be_canceled

      perform_raif_run_jobs
      expect(Raif::DurableRunSecondTestTool.executions).to be_empty
    end

    it "raises out of run! with the host's exception, tagged as a veto" do
      agent = new_agent([Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool])
      script(:stub_raif_agent, Raif::DurableRunTestAgent, [tool_call("durable_run_test_tool", "a", "call_1")])

      expect { agent.run! }.to raise_error(ArgumentError, "durable_run_test_tool is not allowed") { |error|
        expect(error).to be_a(Raif::Errors::ModelToolInvocationAuthorizationError)
      }
      expect(agent.reload).to be_failed
      expect(Raif::DurableRunTestTool.executions).to be_empty
    end

    it "becomes an error result for the model when the agent class treats it as recoverable" do
      allow_any_instance_of(Raif::DurableRunTestAgent).to receive(:recoverable_tool_error?).and_return(true)
      agent = new_agent([Raif::DurableRunTestTool, Raif::DurableRunSecondTestTool])
      script(:stub_raif_agent, Raif::DurableRunTestAgent, two_calls)
      agent.run_later!
      perform_raif_run_jobs

      expect(agent.reload).to be_completed
      expect(agent.conversation_history[2]).to include("tool_error" => true, "provider_tool_call_id" => "call_1")
      expect(agent.conversation_history[2]["result"]).not_to include("not allowed")
      expect(Raif::DurableRunTestTool.executions).to be_empty
      expect(Raif::DurableRunSecondTestTool.executions.length).to eq(1)
    end

    it "fails a conversation entry" do
      conversation = Raif::DurableRunTestConversation.create!(creator: creator)
      script(:stub_raif_conversation, Raif::DurableRunTestConversation, [tool_call("durable_run_test_tool", "only", "call_0")])
      entry = conversation.entries.create!(creator: creator, user_message: "One call", started_at: Time.current)

      entry.process_entry!

      expect(entry.reload).to be_failed
      expect(Raif::DurableRunTestTool.executions).to be_empty
    end

    it "is re-raised by Raif::ModelTool.invoke_tool, which marks the invocation failed" do
      agent = FB.create(:raif_native_tool_calling_agent, creator: creator)

      expect do
        Raif::DurableRunTestTool.invoke_tool(provider_tool_call_id: "call_1", tool_arguments: { "query" => "a" }, source: agent)
      end.to raise_error(Raif::Errors::ModelToolInvocationAuthorizationError)

      expect(agent.raif_model_tool_invocations.sole).to be_failed
      expect(Raif::DurableRunTestTool.executions).to be_empty
    end
  end
end
