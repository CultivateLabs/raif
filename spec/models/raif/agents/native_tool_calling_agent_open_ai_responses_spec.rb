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

    context "with OpenAI Responses" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "open_ai_responses_gpt_4_1_mini" }

      # Match on method+URI rather than the full request body: the request body embeds
      # non-deterministic provider tool-call ids and Wikipedia search results, which makes
      # byte-exact replay matching flaky. Exact request shaping is covered by the adapter
      # specs and the stubbed multi-tool-call replay test below.
      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/open_ai_responses", match_requests_on: [:method, :uri] } do
        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        # The agent reaches a substantive final answer about the JWST.
        expect(agent.final_answer).to be_present
        expect(agent.final_answer.length).to be > 100
        expect(agent.final_answer).to match(/James Webb|JWST/i)

        # search -> read -> answer is a dependent chain, so the model invokes the tools
        # across iterations rather than batching them. Each developer-tool call is
        # immediately followed by its result.
        expect(agent.conversation_history.map { |e| [e["role"], e["type"], e["name"]].compact }).to eq([
          ["user"],
          ["tool_call", "wikipedia_search"],
          ["tool_call_result", "wikipedia_search"],
          ["tool_call", "fetch_url"],
          ["tool_call_result", "fetch_url"],
          ["tool_call", "agent_final_answer"]
        ])

        # Every developer-tool call is paired with a result (valid to replay to the provider).
        calls = agent.conversation_history.select { |e| e["type"] == "tool_call" && e["name"] != "agent_final_answer" }
        results = agent.conversation_history.select { |e| e["type"] == "tool_call_result" }
        expect(results.map { |r| r["provider_tool_call_id"] }).to match_array(calls.map { |c| c["provider_tool_call_id"] })

        invocations = agent.raif_model_tool_invocations.oldest_first.to_a
        expect(invocations.map(&:tool_name)).to eq(%w[wikipedia_search fetch_url agent_final_answer])
        expect(invocations[0].tool_arguments["query"]).to be_present
        expect(invocations[1].tool_arguments["url"]).to match(/en\.wikipedia\.org/)
        expect(invocations[2].result).to eq(agent.final_answer)
      end

      context "when the model returns multiple tool calls in a single iteration" do
        before do
          allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
          stub_request(:get, %r{en\.wikipedia\.org/w/api\.php})
            .to_return(status: 200, body: { query: { search: [] } }.to_json)
          stub_request(:get, "https://example.com")
            .to_return(status: 200, body: "<html><body>Example</body></html>")
        end

        it "invokes both tools and replays them as correctly paired function_call/function_call_output items" do
          multi_call_response = {
            "id" => "resp_1",
            "status" => "completed",
            "output" => [
              {
                "id" => "fc_1",
                "type" => "function_call",
                "status" => "completed",
                "call_id" => "call_1",
                "name" => "wikipedia_search",
                "arguments" => "{\"query\":\"France\"}"
              },
              {
                "id" => "fc_2",
                "type" => "function_call",
                "status" => "completed",
                "call_id" => "call_2",
                "name" => "fetch_url",
                "arguments" => "{\"url\":\"https://example.com\"}"
              }
            ],
            "usage" => { "input_tokens" => 100, "output_tokens" => 30, "total_tokens" => 130 }
          }

          final_answer_response = {
            "id" => "resp_2",
            "status" => "completed",
            "output" => [
              {
                "id" => "fc_3",
                "type" => "function_call",
                "status" => "completed",
                "call_id" => "call_3",
                "name" => "agent_final_answer",
                "arguments" => "{\"final_answer\":\"Paris.\"}"
              }
            ],
            "usage" => { "input_tokens" => 120, "output_tokens" => 20, "total_tokens" => 140 }
          }

          request_bodies = []
          responses = [multi_call_response, final_answer_response]
          stub_request(:post, "https://api.openai.com/v1/responses").to_return do |request|
            request_bodies << JSON.parse(request.body)
            { status: 200, body: responses.shift.to_json, headers: { "Content-Type" => "application/json" } }
          end

          agent.max_iterations = 2
          agent.run!

          expect(agent).to be_completed
          expect(agent.final_answer).to eq("Paris.")
          expect(agent.raif_model_tool_invocations.where(tool_type: "Raif::ModelTools::WikipediaSearch").count).to eq(1)
          expect(agent.raif_model_tool_invocations.where(tool_type: "Raif::ModelTools::FetchUrl").count).to eq(1)

          # The second request replays both calls as interleaved, call_id-paired items.
          second_input = request_bodies.last["input"]
          tool_items = second_input.select { |i| ["function_call", "function_call_output"].include?(i["type"]) }
          expect(tool_items.map { |i| [i["type"], i["call_id"]] }).to eq([
            ["function_call", "call_1"],
            ["function_call_output", "call_1"],
            ["function_call", "call_2"],
            ["function_call_output", "call_2"]
          ])

          # The first request requested parallel tool calls (normal iteration, no forced tool).
          expect(request_bodies.first["parallel_tool_calls"]).to be(true)
        end
      end

      context "when a response is cut off at the max output token limit" do
        before do
          allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
        end

        it "discards the truncated tool call and recovers instead of replaying it" do
          truncated_response = {
            "id" => "resp_1",
            "status" => "incomplete",
            "incomplete_details" => { "reason" => "max_output_tokens" },
            "output" => [
              {
                "id" => "fc_1",
                "type" => "function_call",
                "status" => "incomplete",
                "call_id" => "call_1",
                "name" => "wikipedia_search",
                "arguments" => "{\"query\":\"James Webb Space Telescope OR site:"
              }
            ],
            "usage" => { "input_tokens" => 100, "output_tokens" => 32_768, "total_tokens" => 32_868 }
          }

          final_answer_response = {
            "id" => "resp_2",
            "status" => "completed",
            "output" => [
              {
                "id" => "fc_2",
                "type" => "function_call",
                "status" => "completed",
                "call_id" => "call_2",
                "name" => "agent_final_answer",
                "arguments" => "{\"final_answer\":\"The JWST is the largest space telescope.\"}"
              }
            ],
            "usage" => { "input_tokens" => 120, "output_tokens" => 20, "total_tokens" => 140 }
          }

          request_bodies = []
          responses = [truncated_response, final_answer_response]
          stub_request(:post, "https://api.openai.com/v1/responses").to_return do |request|
            request_bodies << JSON.parse(request.body)
            {
              status: 200,
              body: responses.shift.to_json,
              headers: { "Content-Type" => "application/json" }
            }
          end

          agent.max_iterations = 2
          agent.run!

          expect(agent).to be_completed
          expect(agent).not_to be_failed
          expect(agent.final_answer).to eq("The JWST is the largest space telescope.")

          # The truncated function_call must not be replayed to the provider - OpenAI rejects
          # a function_call input item that has no paired function_call_output.
          second_request_input = request_bodies.last["input"]
          expect(second_request_input.none? { |item| item["type"] == "function_call" }).to be(true)

          input_texts = second_request_input.flat_map { |item| Array(item["content"]).map { |c| c["text"] } }
          expect(input_texts.join("\n")).to include("Error: Your previous response exceeded the maximum output length")
        end
      end
    end
  end
end
