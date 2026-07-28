# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::AgentInferenceStats, type: :model do
  let(:agent) { FB.create(:raif_native_tool_calling_agent) }

  let!(:completions) do
    2.times.map do
      FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        source: agent,
        completed_at: Time.current
      )
    end
  end

  it "reads stats from inference cost events, matching the completions' sums" do
    expect(agent.raif_inference_cost_events.count).to eq(2)

    expect(agent.total_prompt_tokens).to eq(agent.raif_model_completions.sum(:prompt_tokens))
    expect(agent.total_completion_tokens).to eq(agent.raif_model_completions.sum(:completion_tokens))
    expect(agent.total_tokens_sum).to eq(agent.raif_model_completions.sum(:total_tokens))
    expect(agent.total_prompt_token_cost).to eq(agent.raif_model_completions.sum(:prompt_token_cost))
    expect(agent.total_output_token_cost).to eq(agent.raif_model_completions.sum(:output_token_cost))
    expect(agent.total_cost).to eq(agent.raif_model_completions.sum(:total_cost))
  end

  it "keeps returning stats after the completions are culled" do
    expected_prompt_tokens = agent.raif_model_completions.sum(:prompt_tokens)
    expected_total_cost = agent.raif_model_completions.sum(:total_cost)

    Raif::ModelCompletion.where(source: agent).delete_all

    expect(agent.total_prompt_tokens).to eq(expected_prompt_tokens)
    expect(agent.total_cost).to eq(expected_total_cost)
  end
end
