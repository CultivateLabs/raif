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

    context "with OpenRouter/Gemini" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "open_router_gemini_2_5_flash" }

      # Match on method+URI rather than the full request body: the request body embeds
      # non-deterministic provider tool-call ids and Wikipedia search results, which makes
      # byte-exact replay matching flaky. Exact request shaping is covered by the adapter specs.
      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/open_router_gemini", match_requests_on: [:method, :uri] } do
        expect(agent.started_at).to be_nil
        expect(agent.completed_at).to be_nil
        expect(agent.failed_at).to be_nil

        agent.run!

        expect(agent.started_at).to be_present
        expect(agent.completed_at).to be_present
        expect(agent.failed_at).to be_nil

        # Reaches a substantive final answer about the JWST via a tool-using flow.
        expect(agent.final_answer).to be_present
        expect(agent.final_answer.length).to be > 100
        expect(agent.final_answer).to match(/James Webb|JWST/i)

        history = agent.conversation_history
        expect(history.first["role"]).to eq("user")
        expect(history.last).to include("type" => "tool_call", "name" => "agent_final_answer")

        # Every developer-tool call is paired with a result for the same id (valid to replay),
        # and at least one search/read tool ran before the final answer.
        calls = history.select { |e| e["type"] == "tool_call" && e["name"] != "agent_final_answer" }
        results = history.select { |e| e["type"] == "tool_call_result" }
        expect(calls).not_to be_empty
        expect(results.map { |r| r["provider_tool_call_id"] }).to match_array(calls.map { |c| c["provider_tool_call_id"] })

        invocations = agent.raif_model_tool_invocations.oldest_first.to_a
        expect(invocations.map(&:tool_name)).to include("wikipedia_search")
        expect(invocations.last.tool_name).to eq("agent_final_answer")
        expect(invocations.last.result).to eq(agent.final_answer)
      end
    end
  end
end
