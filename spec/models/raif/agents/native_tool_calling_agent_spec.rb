# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_agents
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  completed_at           :datetime
#  conversation_history   :jsonb            not null
#  creator_type           :string           not null
#  failed_at              :datetime
#  failure_reason         :text
#  final_answer           :text
#  iteration_count        :integer          default(0), not null
#  llm_model_key          :string           not null
#  max_iterations         :integer          default(10), not null
#  requested_language_key :string
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  task                   :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint           not null
#  source_id              :bigint
#
# Indexes
#
#  index_raif_agents_on_created_at  (created_at)
#  index_raif_agents_on_creator     (creator_type,creator_id)
#  index_raif_agents_on_source      (source_type,source_id)
#
require "rails_helper"

RSpec.describe Raif::Agents::NativeToolCallingAgent, type: :model do
  let(:creator) { FB.create(:raif_test_user) }

  it_behaves_like "an agent"

  it "validates the length of available_model_tools" do
    agent = described_class.new(
      creator: creator,
      task: "What is the capital of France?",
      system_prompt: "System prompt",
    )
    expect(agent).not_to be_valid
    expect(agent.errors[:available_model_tools]).to include("must have at least 1 tool in addition to the agent_final_answer tool")
  end

  describe "#run!" do
    let(:task) { "What is the capital of France?" }
    let(:llm_model_key) { "open_ai_responses_gpt_4_1" }

    let(:agent) do
      described_class.new(
        creator: creator,
        source: creator,
        task: task,
        max_iterations: 5,
        available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
        llm_model_key: llm_model_key
      )
    end

    it "handles a tool call with an unavailable tool" do
      stub_raif_agent(agent) do |messages, model_completion|
        if messages.length == 1
          model_completion.response_tool_calls = [
            {
              "name" => "unavailable_tool",
              "arguments" => { "query" => "capital of France" }
            }
          ]

          "I'll try to use a non-existent tool."
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]

          "Using the final answer tool now."
        end
      end
      agent.max_iterations = 2
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "name" => "unavailable_tool",
          "arguments" => { "query" => "capital of France" },
          "type" => "tool_call",
          "assistant_message" => "I'll try to use a non-existent tool."
        },
        {
          "role" => "user",
          "content" => "Error: Tool 'unavailable_tool' is not a valid tool. Available tools: wikipedia_search, fetch_url, agent_final_answer"
        },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "provider_tool_call_id" => "call_456",
          "name" => "agent_final_answer",
          "arguments" => { "final_answer" => "Paris is the capital of France." },
          "type" => "tool_call",
          "assistant_message" => "Using the final answer tool now."
        }
      ])
    end

    it "strips extra tool arguments and proceeds with invocation" do
      stub_request(:get, %r{en\.wikipedia\.org/w/api\.php})
        .to_return(status: 200, body: { query: { search: [] } }.to_json)

      stub_raif_agent(agent) do |messages, model_completion|
        if messages.length == 1
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_123",
              "name" => "wikipedia_search",
              "arguments" => { "query" => "capital of France", "length" => 2000, "offset" => 0 }
            }
          ]
          "Let me search for that."
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]
          "The answer is Paris."
        end
      end

      agent.run!

      expect(agent).to be_completed

      # Verify the tool was invoked with only the valid key
      tool_invocation = agent.raif_model_tool_invocations.find_by(tool_type: "Raif::ModelTools::WikipediaSearch")
      expect(tool_invocation).to be_present
      expect(tool_invocation.tool_arguments).to eq("query" => "capital of France")

      # Verify conversation history records the prepared (not raw) arguments
      tool_call_entry = agent.conversation_history.find { |e| e["name"] == "wikipedia_search" }
      expect(tool_call_entry["arguments"]).to eq("query" => "capital of France")
      expect(tool_call_entry["arguments"]).not_to have_key("length")
    end

    it "handles a tool call with invalid tool arguments" do
      stub_raif_agent(agent) do |messages, model_completion|
        if messages.length == 1
          model_completion.response_tool_calls = [
            {
              "name" => "wikipedia_search",
              "arguments" => { "search_term" => "jingle bells" }
            }
          ]

          "I'll try to use Wikipedia search with wrong arguments."
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]

          "Using the final answer tool now."
        end
      end

      agent.max_iterations = 2
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "name" => "wikipedia_search",
          "arguments" => {},
          "type" => "tool_call",
          "assistant_message" => "I'll try to use Wikipedia search with wrong arguments."
        },
        {
          "role" => "user",
          "content" =>
          "Error: Invalid tool arguments for the tool 'wikipedia_search'. Tool arguments schema: {\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"The query to search Wikipedia for\"}},\"required\":[\"query\"]}" # rubocop:disable Layout/LineLength
        },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "provider_tool_call_id" => "call_456",
          "name" => "agent_final_answer",
          "arguments" => { "final_answer" => "Paris is the capital of France." },
          "type" => "tool_call",
          "assistant_message" => "Using the final answer tool now."
        }
      ])
    end

    it "handles an iteration with no tool call" do
      stub_raif_agent(agent) do |messages, model_completion|
        if messages.length == 1
          model_completion.response_tool_calls = nil

          "Maybe I'll just jabber instead of using a tool"
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]

          "Using the final answer tool now."
        end
      end

      agent.max_iterations = 2
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "assistant",
          "content" => "Maybe I'll just jabber instead of using a tool"
        },
        {
          "role" => "user",
          "content" => "Error: Previous message contained no tool call. Make a tool call at each step. Available tools: wikipedia_search, fetch_url, agent_final_answer" # rubocop:disable Layout/LineLength
        },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "provider_tool_call_id" => "call_456",
          "name" => "agent_final_answer",
          "arguments" => { "final_answer" => "Paris is the capital of France." },
          "type" => "tool_call",
          "assistant_message" => "Using the final answer tool now."
        }
      ])
    end

    it "forces the required tool on an earlier iteration and adds a warning" do
      tool_choices = []

      allow(agent).to receive(:required_tool_for_iteration) { agent.send(:final_answer_tool) }

      stub_raif_agent(agent) do |_messages, model_completion|
        tool_choices << model_completion.tool_choice
        model_completion.response_tool_calls = [
          {
            "provider_tool_call_id" => "call_123",
            "name" => "agent_final_answer",
            "arguments" => { "final_answer" => "Paris is the capital of France." }
          }
        ]

        "Using the final answer tool now."
      end

      agent.max_iterations = 2
      agent.run!

      expect(tool_choices).to eq(["Raif::ModelTools::AgentFinalAnswer"])
      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "user",
          "content" => "Warning: This iteration requires the agent_final_answer tool. If you do not use it now, the next iteration will be your final chance."
        },
        {
          "provider_tool_call_id" => "call_123",
          "name" => "agent_final_answer",
          "arguments" => { "final_answer" => "Paris is the capital of France." },
          "type" => "tool_call",
          "assistant_message" => "Using the final answer tool now."
        }
      ])
    end

    it "memoizes the required tool within a single iteration" do
      required_tool_calls = 0

      allow(agent).to receive(:required_tool_for_iteration) do
        required_tool_calls += 1
        agent.send(:final_answer_tool)
      end

      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "provider_tool_call_id" => "call_123",
            "name" => "agent_final_answer",
            "arguments" => { "final_answer" => "Paris is the capital of France." }
          }
        ]

        "Using the final answer tool now."
      end

      agent.max_iterations = 1
      agent.run!

      expect(required_tool_calls).to eq(1)
    end

    it "retries when a required tool is missed and another iteration remains" do
      allow(agent).to receive(:required_tool_for_iteration) { agent.send(:final_answer_tool) }

      stub_raif_agent(agent) do |messages, model_completion|
        if messages.length == 2
          model_completion.response_tool_calls = nil
          "Maybe I'll just jabber instead of using a tool"
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]
          "Using the final answer tool now."
        end
      end

      agent.max_iterations = 2
      agent.run!

      expect(agent).to be_completed
      expect(agent).not_to be_failed
      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "user",
          "content" => "Warning: This iteration requires the agent_final_answer tool. If you do not use it now, the next iteration will be your final chance."
        },
        {
          "role" => "assistant",
          "content" => "Maybe I'll just jabber instead of using a tool"
        },
        {
          "role" => "user",
          "content" => "Error: This iteration required the tool 'agent_final_answer', but the model response contained no tool call. Available tools: wikipedia_search, fetch_url, agent_final_answer"
        },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "provider_tool_call_id" => "call_456",
          "name" => "agent_final_answer",
          "arguments" => { "final_answer" => "Paris is the capital of France." },
          "type" => "tool_call",
          "assistant_message" => "Using the final answer tool now."
        }
      ])
    end

    it "fails when no tool call is returned on the final allowed required-tool attempt" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = nil

        "Maybe I'll just jabber instead of using a tool"
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent).to be_failed
      expect(agent).not_to be_completed
      expect(agent.failure_reason).to eq(
        "Error: This iteration required the tool 'agent_final_answer', but the model response contained no tool call. Available tools: wikipedia_search, fetch_url, agent_final_answer"
      )
      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "role" => "assistant",
          "content" => "Maybe I'll just jabber instead of using a tool"
        },
        {
          "role" => "user",
          "content" => "Error: This iteration required the tool 'agent_final_answer', but the model response contained no tool call. Available tools: wikipedia_search, fetch_url, agent_final_answer"
        }
      ])
    end

    it "fails when a different tool is called on the final allowed required-tool attempt" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "wikipedia_search",
            "arguments" => { "query" => "capital of France" }
          }
        ]

        "I'll search instead of using the final answer tool."
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent).to be_failed
      expect(agent).not_to be_completed
      expect(agent.failure_reason).to eq(
        "Error: This iteration required the tool 'agent_final_answer', but the model called 'wikipedia_search' instead."
      )
      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "name" => "wikipedia_search",
          "arguments" => { "query" => "capital of France" },
          "type" => "tool_call",
          "assistant_message" => "I'll search instead of using the final answer tool."
        },
        {
          "role" => "user",
          "content" => "Error: This iteration required the tool 'agent_final_answer', but the model called 'wikipedia_search' instead."
        }
      ])
    end

    it "fails if it exhausts iterations without calling agent_final_answer" do
      allow(agent).to receive(:required_tool_for_iteration).and_return(nil)

      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "unavailable_tool",
            "arguments" => { "query" => "capital of France" }
          }
        ]

        "I'll try to use a non-existent tool."
      end

      agent.max_iterations = 2
      agent.run!

      expect(agent).to be_failed
      expect(agent).not_to be_completed
      expect(agent.failure_reason).to eq("Agent completed without calling agent_final_answer")
    end

    it "defaults tool_choice to :required when no specific tool is required" do
      tool_choices = []

      stub_raif_agent(agent) do |messages, model_completion|
        tool_choices << model_completion.tool_choice

        if messages.length == 1
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_123",
              "name" => "wikipedia_search",
              "arguments" => { "query" => "capital of France" }
            }
          ]
          "Let me search for that."
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]
          "The answer is Paris."
        end
      end

      stub_request(:get, %r{en\.wikipedia\.org/w/api\.php})
        .to_return(status: 200, body: { query: { search: [] } }.to_json)

      agent.max_iterations = 5
      agent.run!

      expect(tool_choices.first).to eq("required")
    end

    it "handles multiple tool calls by returning an error" do
      stub_raif_agent(agent) do |messages, model_completion|
        if messages.length == 1
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_1",
              "name" => "wikipedia_search",
              "arguments" => { "query" => "capital of France" }
            },
            {
              "provider_tool_call_id" => "call_2",
              "name" => "fetch_url",
              "arguments" => { "url" => "https://example.com" }
            }
          ]
          "Let me search and fetch at the same time."
        else
          model_completion.response_tool_calls = [
            {
              "provider_tool_call_id" => "call_456",
              "name" => "agent_final_answer",
              "arguments" => { "final_answer" => "Paris is the capital of France." }
            }
          ]
          "Using the final answer tool now."
        end
      end

      agent.max_iterations = 2
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        {
          "role" => "assistant",
          "content" => "Let me search and fetch at the same time."
        },
        {
          "role" => "user",
          "content" => "Error: Multiple tool calls received. Only one tool call is allowed per step. Please call exactly one tool at a time."
        },
        {
          "role" => "user",
          "content" => "Warning: This is your final iteration. You must provide your final answer using the agent_final_answer tool."
        },
        {
          "provider_tool_call_id" => "call_456",
          "name" => "agent_final_answer",
          "arguments" => { "final_answer" => "Paris is the capital of France." },
          "type" => "tool_call",
          "assistant_message" => "Using the final answer tool now."
        }
      ])
    end

    it "fails when multiple tool calls are returned on the final required-tool attempt" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "provider_tool_call_id" => "call_1",
            "name" => "agent_final_answer",
            "arguments" => { "final_answer" => "Paris" }
          },
          {
            "provider_tool_call_id" => "call_2",
            "name" => "wikipedia_search",
            "arguments" => { "query" => "France" }
          }
        ]
        "Here's the answer and a search."
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent).to be_failed
      expect(agent.failure_reason).to eq(
        "Error: Multiple tool calls received. Only one tool call is allowed per step. Please call exactly one tool at a time."
      )
    end
  end

  describe "failure handling" do
    let(:agent) do
      described_class.create!(
        creator: creator,
        source: creator,
        task: "What is the capital of France?",
        max_iterations: 1,
        available_model_tools: [Raif::ModelTools::WikipediaSearch],
        llm_model_key: "open_ai_responses_gpt_4_1"
      )
    end

    it "preserves the first failure reason" do
      agent.send(:fail_run!, "First failure")
      first_failed_at = agent.failed_at

      agent.send(:fail_run!, "Second failure")

      expect(agent.failed_at).to eq(first_failed_at)
      expect(agent.failure_reason).to eq("First failure")
    end
  end

  describe "#build_system_prompt" do
    let(:task) { "What is the capital of France?" }
    let(:tools) { [Raif::TestModelTool, Raif::ModelTools::WikipediaSearch] }
    let(:agent) { described_class.new(task: task, available_model_tools: tools, creator: creator) }

    it "builds the system prompt" do
      prompt = <<~PROMPT.strip
        You are an AI agent that follows the ReAct (Reasoning + Acting) framework to complete tasks step by step using tool/function calls.

        At each step, you must:
        1. Think about what to do next.
        2. Choose and invoke exactly one tool/function call based on that thought.
        3. Observe the results of the tool/function call.
        4. Use the results to update your thought process.
        5. Repeat steps 1-4 until the task is complete.
        6. Provide a final answer to the user's request.

        For your final answer:
        - You **MUST** use the agent_final_answer tool/function to provide your final answer.
        - Your answer should be comprehensive and directly address the user's request.

        Guidelines
        - Always think step by step
        - Be concise in your reasoning but thorough in your analysis
        - If a tool returns an error, try to understand why and adjust your approach
        - If you're unsure about something, explain your uncertainty, but do not make things up
        - Always provide a final answer that directly addresses the user's request

        Remember: Your goal is to be helpful, accurate, and efficient in solving the user's request.
      PROMPT

      expect(agent.build_system_prompt).to eq(prompt)
    end
  end

  describe "validations" do
    it "validates that the LLM supports native tool use" do
      agent = described_class.new(
        creator: creator,
        task: "test",
        llm_model_key: "raif_test_llm"
      )

      agent.llm.supports_native_tool_use = false

      expect(agent).not_to be_valid
      expect(agent.errors[:base]).to include("Raif::Agent#llm_model_key must use an LLM that supports native tool use")
    end
  end

  describe "final answer tool" do
    it "adds the final answer tool to the available model tools" do
      agent = described_class.create!(
        creator: creator,
        task: "What is the capital of France?",
        available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl]
      )

      expect(agent.available_model_tools_map["agent_final_answer"]).to eq(Raif::ModelTools::AgentFinalAnswer)
    end

    it "doesn't add a final answer tool to the available model tools one is already defined" do
      custom_tool_class = Class.new(Raif::ModelTool) do
        # Force the tool_name to collide with the built-in final answer tool
        def self.tool_name
          "agent_final_answer"
        end

        # Define minimal required class methods for a model tool
        def self.tool_description
          "Custom final answer tool"
        end

        def self.example_model_invocation
          { "name" => tool_name, "arguments" => { "final_answer" => "Example" } }
        end

        def self.tool_arguments_schema
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => { "final_answer" => { "type" => "string" } },
            "required" => ["final_answer"]
          }
        end

        def self.process_invocation(tool_invocation)
          tool_invocation.update!(result: { "final_answer" => tool_invocation.tool_arguments["final_answer"] })
          tool_invocation.result
        end

        def self.observation_for_invocation(tool_invocation)
          tool_invocation.result&.fetch("final_answer", "")
        end
      end

      stub_const("CustomFinalAnswerTool", custom_tool_class)

      custom_agent = described_class.create!(
        creator: creator,
        task: "What is the capital of France?",
        available_model_tools: [Raif::ModelTools::WikipediaSearch, CustomFinalAnswerTool]
      )

      # The custom tool with name "agent_final_answer" should be used, not the built-in one
      expect(custom_agent.available_model_tools_map["agent_final_answer"]).to eq(CustomFinalAnswerTool)

      # Ensure the built-in tool was NOT auto-added
      tool_class_names = custom_agent.available_model_tools.map { |t| t.is_a?(String) ? t : t.name }
      expect(tool_class_names).to_not include("Raif::ModelTools::AgentFinalAnswer")
    end
  end
end
