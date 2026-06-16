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

    context "with Bedrock" do
      let(:task) { "Tell me some interesting facts from the James Webb Space Telescope's Wikipedia page" }
      let(:llm_model_key) { "bedrock_claude_4_5_haiku" }

      before do
        allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
        allow(Raif.config).to receive(:bedrock_models_enabled).and_return(true)

        # To record new VCR cassettes, set real credentials here.
        stubbed_creds = Aws::Credentials.new("placeholder-bedrock-access-key", "placeholder-bedrock-secret-key")
        client = Aws::BedrockRuntime::Client.new(
          region: Raif.config.aws_bedrock_region,
          credentials: stubbed_creds
        )

        allow_any_instance_of(Raif::Llms::Bedrock).to receive(:bedrock_client).and_return(client)
      end

      it "sends a forced Bedrock tool choice when a required tool is activated before the final iteration" do
        answer = "Paris is the capital of France."
        response = Aws::BedrockRuntime::Types::ConverseResponse.new(
          output: Aws::BedrockRuntime::Types::ConverseOutput::Message.new(
            message: Aws::BedrockRuntime::Types::Message.new(
              role: "assistant",
              content: [
                Aws::BedrockRuntime::Types::ContentBlock.new(text: "Using the final answer tool now."),
                Aws::BedrockRuntime::Types::ContentBlock.new(
                  tool_use: Aws::BedrockRuntime::Types::ToolUseBlock.new(
                    tool_use_id: "tooluse_abc123",
                    name: "agent_final_answer",
                    input: { "final_answer" => answer }
                  )
                )
              ]
            )
          ),
          usage: Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15),
          stop_reason: "tool_use"
        )

        mock_client = instance_double(Aws::BedrockRuntime::Client)
        allow_any_instance_of(Raif::Llms::Bedrock).to receive(:bedrock_client).and_return(mock_client)
        allow(agent).to receive(:required_tool_for_iteration) { agent.send(:final_answer_tool) }

        expect(mock_client).to receive(:converse) do |params|
          expect(params.dig(:tool_config, :tool_choice)).to eq(tool: { name: "agent_final_answer" })
          response
        end

        agent.max_iterations = 2
        agent.run!

        expect(agent).to be_completed
        expect(agent.final_answer).to eq(answer)
        expect(agent.raif_model_completions.oldest_first.first.tool_choice).to eq("Raif::ModelTools::AgentFinalAnswer")
      end

      # Bedrock's Converse calls all share one URI, so they can only be sequenced by body.
      # Provider tool-call ids in request bodies are normalized to stable placeholders by the
      # VCR before_record hook so the recorded request matches the replayed one.
      it "processes multiple iterations until finding an answer",
        vcr: { cassette_name: "native_tool_calling_agent/bedrock", allow_playback_repeats: true } do
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
