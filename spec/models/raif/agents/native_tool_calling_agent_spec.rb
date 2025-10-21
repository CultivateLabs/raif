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
    let(:agent) do
      described_class.new(
        creator: creator,
        source: creator,
        task: "What is the capital of France?",
        max_iterations: 3,
        available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
        llm_model_key: "open_ai_gpt_4o"
      )
    end

    it "runs the agent" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "agent_final_answer",
            "arguments" => { "final_answer" => "Paris" }
          }
        ]

        "I know this."
      end

      expect(agent.started_at).to be_nil
      expect(agent.completed_at).to be_nil
      expect(agent.failed_at).to be_nil

      agent.run!

      expect(agent.started_at).to be_present
      expect(agent.completed_at).to be_present
      expect(agent.failed_at).to be_nil
      expect(agent.creator).to eq(creator)
      expect(agent.source).to eq(creator)

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        { "role" => "assistant", "content" => "I know this." },
        { "role" => "assistant", "content" => "<answer>\nParis\n</answer>" }
      ])

      expect(agent.final_answer).to eq("Paris")
    end

    context "with multiple iterations" do
      before do
        stub_request(:get, "https://en.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=5&srprop=snippet&srsearch=capital%20of%20France")
          .to_return(status: 200, body: "{\"batchcomplete\":\"\",\"continue\":{\"sroffset\":5,\"continue\":\"-||\"},\"query\":{\"searchinfo\":{\"totalhits\":93901},\"search\":[{\"ns\":0,\"title\":\"List of capitals of France\",\"pageid\":169335,\"snippet\":\"This is a chronological list <span class=\\\"searchmatch\\\">of</span> capitals <span class=\\\"searchmatch\\\">of</span> <span class=\\\"searchmatch\\\">France</span>. The <span class=\\\"searchmatch\\\">capital</span> <span class=\\\"searchmatch\\\">of</span> <span class=\\\"searchmatch\\\">France</span> has been Paris since its liberation in 1944. Tournai (before 486), current-day\"},{\"ns\":0,\"title\":\"Capital punishment in France\",\"pageid\":2861364,\"snippet\":\"<span class=\\\"searchmatch\\\">Capital</span> punishment in <span class=\\\"searchmatch\\\">France</span> (<span class=\\\"searchmatch\\\">French</span>: peine de mort en <span class=\\\"searchmatch\\\">France</span>) is banned by Article 66-1 <span class=\\\"searchmatch\\\">of</span> the Constitution <span class=\\\"searchmatch\\\">of</span> the <span class=\\\"searchmatch\\\">French</span> Republic, voted as a constitutional\"},{\"ns\":0,\"title\":\"Capital city\",\"pageid\":181337,\"snippet\":\"seat <span class=\\\"searchmatch\\\">of</span> the government. A <span class=\\\"searchmatch\\\">capital</span> is typically a city that physically encompasses the government&#039;s offices and meeting places; the status as <span class=\\\"searchmatch\\\">capital</span> is\"},{\"ns\":0,\"title\":\"Capital\",\"pageid\":5187,\"snippet\":\"Piketty, 2013 <span class=\\\"searchmatch\\\">Capital</span>: The Eruption <span class=\\\"searchmatch\\\">of</span> Delhi, a 2014 book by Rana Dasgupta <span class=\\\"searchmatch\\\">Capital</span> (<span class=\\\"searchmatch\\\">French</span> magazine), a <span class=\\\"searchmatch\\\">French</span>-language magazine <span class=\\\"searchmatch\\\">Capital</span> (German magazine)\"},{\"ns\":0,\"title\":\"Paris\",\"pageid\":22989,\"snippet\":\"Paris (<span class=\\\"searchmatch\\\">French</span> pronunciation: [pa\\u0281i] ) is the <span class=\\\"searchmatch\\\">capital</span> and largest city <span class=\\\"searchmatch\\\">of</span> <span class=\\\"searchmatch\\\">France</span>. With an estimated population <span class=\\\"searchmatch\\\">of</span> 2,048,472 residents in January 2025 in\"}]}}") # rubocop:disable Layout/LineLength
      end

      it "processes multiple iterations until finding an answer" do
        i = 0
        stub_raif_agent(agent) do |_messages, model_completion|
          i += 1
          if i == 1
            model_completion.response_tool_calls = [
              {
                "name" => "wikipedia_search",
                "arguments" => { "query" => "capital of France" }
              }
            ]

            "I need to search Wikipedia."
          else
            model_completion.response_tool_calls = [
              {
                "name" => "agent_final_answer",
                "arguments" => { "final_answer" => "Paris" }
              }
            ]

            "Based on the search results, I can now answer."
          end
        end

        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil
        expect(agent.final_answer).to eq("Paris")

        expect(agent.conversation_history).to eq([
          { "role" => "user", "content" => "What is the capital of France?" },
          { "role" => "assistant", "content" => "I need to search Wikipedia." },
          {
            "role" => "assistant",
            "content" => "<action>\n{\n  \"name\": \"wikipedia_search\",\n  \"arguments\": {\n    \"query\": \"capital of France\"\n  }\n}\n</action>"
          },
          {
            "role" => "assistant",
            "content" =>
            "<observation>\n{\n  \"results\": [\n    {\n      \"title\": \"List of capitals of France\",\n      \"snippet\": \"This is a chronological list <span class=\\\"searchmatch\\\">of</span> capitals <span class=\\\"searchmatch\\\">of</span> <span class=\\\"searchmatch\\\">France</span>. The <span class=\\\"searchmatch\\\">capital</span> <span class=\\\"searchmatch\\\">of</span> <span class=\\\"searchmatch\\\">France</span> has been Paris since its liberation in 1944. Tournai (before 486), current-day\",\n      \"page_id\": 169335,\n      \"url\": \"https://en.wikipedia.org/wiki/List_of_capitals_of_France\"\n    },\n    {\n      \"title\": \"Capital punishment in France\",\n      \"snippet\": \"<span class=\\\"searchmatch\\\">Capital</span> punishment in <span class=\\\"searchmatch\\\">France</span> (<span class=\\\"searchmatch\\\">French</span>: peine de mort en <span class=\\\"searchmatch\\\">France</span>) is banned by Article 66-1 <span class=\\\"searchmatch\\\">of</span> the Constitution <span class=\\\"searchmatch\\\">of</span> the <span class=\\\"searchmatch\\\">French</span> Republic, voted as a constitutional\",\n      \"page_id\": 2861364,\n      \"url\": \"https://en.wikipedia.org/wiki/Capital_punishment_in_France\"\n    },\n    {\n      \"title\": \"Capital city\",\n      \"snippet\": \"seat <span class=\\\"searchmatch\\\">of</span> the government. A <span class=\\\"searchmatch\\\">capital</span> is typically a city that physically encompasses the government&#039;s offices and meeting places; the status as <span class=\\\"searchmatch\\\">capital</span> is\",\n      \"page_id\": 181337,\n      \"url\": \"https://en.wikipedia.org/wiki/Capital_city\"\n    },\n    {\n      \"title\": \"Capital\",\n      \"snippet\": \"Piketty, 2013 <span class=\\\"searchmatch\\\">Capital</span>: The Eruption <span class=\\\"searchmatch\\\">of</span> Delhi, a 2014 book by Rana Dasgupta <span class=\\\"searchmatch\\\">Capital</span> (<span class=\\\"searchmatch\\\">French</span> magazine), a <span class=\\\"searchmatch\\\">French</span>-language magazine <span class=\\\"searchmatch\\\">Capital</span> (German magazine)\",\n      \"page_id\": 5187,\n      \"url\": \"https://en.wikipedia.org/wiki/Capital\"\n    },\n    {\n      \"title\": \"Paris\",\n      \"snippet\": \"Paris (<span class=\\\"searchmatch\\\">French</span> pronunciation: [paʁi] ) is the <span class=\\\"searchmatch\\\">capital</span> and largest city <span class=\\\"searchmatch\\\">of</span> <span class=\\\"searchmatch\\\">France</span>. With an estimated population <span class=\\\"searchmatch\\\">of</span> 2,048,472 residents in January 2025 in\",\n      \"page_id\": 22989,\n      \"url\": \"https://en.wikipedia.org/wiki/Paris\"\n    }\n  ]\n}\n</observation>" # rubocop:disable Layout/LineLength
          },
          { "role" => "assistant", "content" => "Based on the search results, I can now answer." },
          { "role" => "assistant", "content" => "<answer>\nParis\n</answer>" }
        ])

        expect(agent.raif_model_tool_invocations.length).to eq(2)
        mti = agent.raif_model_tool_invocations.oldest_first.first
        expect(mti.tool_name).to eq("wikipedia_search")
        expect(mti.tool_type).to eq("Raif::ModelTools::WikipediaSearch")
        expect(mti.tool_arguments).to eq({ "query" => "capital of France" })

        expect(mti.result).to eq({
          "results" => [
            {
              "url" => "https://en.wikipedia.org/wiki/List_of_capitals_of_France",
              "title" => "List of capitals of France",
              "page_id" => 169335,
              "snippet" => "This is a chronological list <span class=\"searchmatch\">of</span> capitals <span class=\"searchmatch\">of</span> <span class=\"searchmatch\">France</span>. The <span class=\"searchmatch\">capital</span> <span class=\"searchmatch\">of</span> <span class=\"searchmatch\">France</span> has been Paris since its liberation in 1944. Tournai (before 486), current-day" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Capital_punishment_in_France",
              "title" => "Capital punishment in France",
              "page_id" => 2861364,
              "snippet" => "<span class=\"searchmatch\">Capital</span> punishment in <span class=\"searchmatch\">France</span> (<span class=\"searchmatch\">French</span>: peine de mort en <span class=\"searchmatch\">France</span>) is banned by Article 66-1 <span class=\"searchmatch\">of</span> the Constitution <span class=\"searchmatch\">of</span> the <span class=\"searchmatch\">French</span> Republic, voted as a constitutional" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Capital_city",
              "title" => "Capital city",
              "page_id" => 181337,
              "snippet" => "seat <span class=\"searchmatch\">of</span> the government. A <span class=\"searchmatch\">capital</span> is typically a city that physically encompasses the government&#039;s offices and meeting places; the status as <span class=\"searchmatch\">capital</span> is" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Capital",
              "title" => "Capital",
              "page_id" => 5187,
              "snippet" => "Piketty, 2013 <span class=\"searchmatch\">Capital</span>: The Eruption <span class=\"searchmatch\">of</span> Delhi, a 2014 book by Rana Dasgupta <span class=\"searchmatch\">Capital</span> (<span class=\"searchmatch\">French</span> magazine), a <span class=\"searchmatch\">French</span>-language magazine <span class=\"searchmatch\">Capital</span> (German magazine)" # rubocop:disable Layout/LineLength
            },
            {
              "url" => "https://en.wikipedia.org/wiki/Paris",
              "title" => "Paris",
              "page_id" => 22989,
              "snippet" => "Paris (<span class=\"searchmatch\">French</span> pronunciation: [paʁi] ) is the <span class=\"searchmatch\">capital</span> and largest city <span class=\"searchmatch\">of</span> <span class=\"searchmatch\">France</span>. With an estimated population <span class=\"searchmatch\">of</span> 2,048,472 residents in January 2025 in" # rubocop:disable Layout/LineLength
            }
          ]
        })

        mti2 = agent.raif_model_tool_invocations.oldest_first.second
        expect(mti2.tool_name).to eq("agent_final_answer")
        expect(mti2.tool_type).to eq("Raif::ModelTools::AgentFinalAnswer")
        expect(mti2.tool_arguments).to eq({ "final_answer" => "Paris" })
        expect(mti2.result).to eq({ "final_answer" => "Paris" })
      end
    end

    it "handles a tool call with an unavailable tool" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "unavailable_tool",
            "arguments" => { "query" => "capital of France" }
          }
        ]

        "I'll try to use a non-existent tool."
      end
      agent.max_iterations = 1
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        { "role" => "assistant", "content" => "I'll try to use a non-existent tool." },
        {
          "role" => "assistant",
          "content" => "<action>\n{\n  \"name\": \"unavailable_tool\",\n  \"arguments\": {\n    \"query\": \"capital of France\"\n  }\n}\n</action>"
        },
        {
          "role" => "assistant",
          "content" =>
          "<observation>Error: Tool 'unavailable_tool' not found. Available tools: wikipedia_search, fetch_url, agent_final_answer</observation>"
        }
      ])
    end

    it "handles a tool call with invalid tool arguments" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = [
          {
            "name" => "wikipedia_search",
            "arguments" => { "search_term" => "jingle bells" }
          }
        ]

        "I'll try to use Wikipedia search with wrong arguments."
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        { "role" => "assistant", "content" => "I'll try to use Wikipedia search with wrong arguments." },
        {
          "role" => "assistant",
          "content" => "<action>\n{\n  \"name\": \"wikipedia_search\",\n  \"arguments\": {\n    \"search_term\": \"jingle bells\"\n  }\n}\n</action>"
        },
        {
          "role" => "assistant",
          "content" =>
          "<observation>Error: Invalid tool arguments. Please provide valid arguments for the tool 'wikipedia_search'. Tool arguments schema: {\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"The query to search Wikipedia for\"}},\"required\":[\"query\"]}</observation>" # rubocop:disable Layout/LineLength
        }
      ])
    end

    it "handles an iteration with no tool call" do
      stub_raif_agent(agent) do |_messages, model_completion|
        model_completion.response_tool_calls = nil

        "Maybe I'll just jabber instead of using a tool"
      end

      agent.max_iterations = 1
      agent.run!

      expect(agent.conversation_history).to eq([
        { "role" => "user", "content" => "What is the capital of France?" },
        { "role" => "assistant", "content" => "Maybe I'll just jabber instead of using a tool" },
        {
          "role" => "assistant",
          "content" =>
          "<observation>Error: No tool call found. I need to make a tool call at each step. Available tools: wikipedia_search, fetch_url, agent_final_answer</observation>" # rubocop:disable Layout/LineLength
        }
      ])
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
        - Use the agent_final_answer tool/function with your complete answer as the "final_answer" parameter.
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
