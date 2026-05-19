# frozen_string_literal: true

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
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-20241022",
        available_model_tools: ["Raif::ModelTools::ProviderManaged::WebSearch"],
        response_array: [
          { "type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => { "query" => "q1" } },
          { "type" => "server_tool_use", "id" => "srvtoolu_2", "name" => "web_search", "input" => { "query" => "q2" } },
        ]
      )

      FB.create(
        :raif_model_completion,
        source: agent,
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-20241022",
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
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-20241022",
        available_model_tools: [],
        response_array: [
          { "type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => { "query" => "q1" } },
        ]
      )

      expect(agent.model_tool_invocation_counts).to eq({})
    end
  end
end
