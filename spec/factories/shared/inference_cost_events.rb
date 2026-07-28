# frozen_string_literal: true

FactoryBot.define do
  factory :raif_inference_cost_event, class: "Raif::InferenceCostEvent" do
    llm_model_key { Raif.available_llm_keys.sample.to_s }
    model_api_name { "raif-test-llm" }
    sequence(:original_model_completion_id)
    incurred_at { Time.current }
    prompt_tokens { rand(10..50) }
    completion_tokens { rand(20..100) }
    total_tokens { prompt_tokens + completion_tokens }

    trait :with_costs do
      prompt_token_cost { 0.000123 }
      output_token_cost { 0.000456 }
      total_cost { 0.000579 }
    end
  end
end
