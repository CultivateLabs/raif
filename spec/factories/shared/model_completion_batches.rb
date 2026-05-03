# frozen_string_literal: true

FactoryBot.define do
  factory :raif_model_completion_batch_anthropic, class: "Raif::ModelCompletionBatches::Anthropic" do
    llm_model_key { "anthropic_claude_3_5_haiku" }
    model_api_name { "claude-3-5-haiku-latest" }
    status { "pending" }
  end

  factory :raif_model_completion_batch_open_ai, class: "Raif::ModelCompletionBatches::OpenAi" do
    llm_model_key { "open_ai_responses_gpt_4o" }
    model_api_name { "gpt-4o" }
    status { "pending" }
  end
end
