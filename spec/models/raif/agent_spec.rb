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

RSpec.describe Raif::Agent, type: :model do
  let(:creator) { FB.create(:raif_test_user) }

  describe "#model_tool_invocation_counts" do
    let(:agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        system_prompt: "System prompt",
        available_model_tools: [
          "Raif::ModelTools::WikipediaSearch",
          "Raif::ModelTools::ProviderManaged::WebSearch",
        ]
      )
    end

    it "combines developer-managed invocation rows with provider-managed tool calls extracted from completions" do
      FB.create(:raif_model_tool_invocation, source: agent)
      FB.create(:raif_model_tool_invocation, source: agent)

      FB.create(
        :raif_model_completion,
        source: agent,
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        available_model_tools: ["Raif::ModelTools::ProviderManaged::WebSearch"],
        response_array: [
          { "type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => { "query" => "q1" } },
          { "type" => "server_tool_use", "id" => "srvtoolu_2", "name" => "web_search", "input" => { "query" => "q2" } },
        ]
      )

      FB.create(
        :raif_model_completion,
        source: agent,
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        available_model_tools: ["Raif::ModelTools::ProviderManaged::WebSearch"],
        response_array: [
          { "type" => "server_tool_use", "id" => "srvtoolu_3", "name" => "web_search", "input" => { "query" => "q3" } },
        ]
      )

      expect(agent.model_tool_invocation_counts).to eq(
        "Raif::TestModelTool" => 2,
        "Raif::ModelTools::ProviderManaged::WebSearch" => 3
      )
    end

    it "ignores provider-managed tool calls for tools not registered on the completion" do
      FB.create(
        :raif_model_completion,
        source: agent,
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        available_model_tools: [],
        response_array: [
          { "type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => { "query" => "q1" } },
        ]
      )

      expect(agent.model_tool_invocation_counts).to eq({})
    end
  end

  describe "#add_conversation_history_entry" do
    let(:agent) do
      FB.create(
        :raif_native_tool_calling_agent,
        creator: creator,
        system_prompt: "System prompt",
        available_model_tools: [
          "Raif::ModelTools::WikipediaSearch",
          "Raif::ModelTools::ProviderManaged::WebSearch",
        ]
      )
    end

    # A NUL byte (e.g. from a corrupted scraped page) in a tool result would
    # otherwise abort the save! with PG::UntranslatableCharacter, since
    # Postgres cannot store NUL bytes in a jsonb column.
    it "strips NUL bytes from string, nested hash, and array content before persisting to the jsonb column" do
      nul = 0.chr
      entry = {
        "type" => "tool_call_result",
        "name" => "fetch_url",
        "result" => {
          "content" => "announced later in 2026 in a communiqu#{nul}#{nul}",
          "links" => ["https://example.com/a#{nul}b", "https://example.com/c"]
        }
      }

      expect { agent.send(:add_conversation_history_entry, entry) }.not_to raise_error

      persisted = agent.reload.conversation_history.last
      expect(persisted["result"]["content"]).to eq("announced later in 2026 in a communiqu")
      expect(persisted["result"]["links"]).to eq(["https://example.com/ab", "https://example.com/c"])
      expect(agent.conversation_history.to_json).not_to include(nul)
    end
  end
end
