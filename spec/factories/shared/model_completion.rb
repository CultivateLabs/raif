# frozen_string_literal: true

FactoryBot.define do
  factory :raif_model_completion, class: "Raif::ModelCompletion" do
    llm_model_key { Raif.available_llm_keys.sample.to_s }
    response_format { Raif::Llm.valid_response_formats.sample.to_s }
    sequence(:raw_response) { |i| "Model response #{i} #{SecureRandom.hex(4)}" }
    messages { [{ "role" => "user", "content" => "Test message" }] }
    prompt_tokens { rand(10..50) }
    completion_tokens { rand(20..100) }
    total_tokens { prompt_tokens + completion_tokens }

    trait :with_json_response do
      response_format { "json" }
      raw_response { '{"message": "This is a JSON response", "data": {"key": "value"}}' }
    end

    trait :with_html_response do
      response_format { "html" }
      raw_response { '<div class="response">This is an HTML response</div>' }
    end
  end

  factory :raif_test_model_completion, class: "Raif::ModelCompletions::Test" do
    llm_model_key { "raif_test_llm" }
    response_format { "text" }
    raw_response { "Test model response" }
  end
end
