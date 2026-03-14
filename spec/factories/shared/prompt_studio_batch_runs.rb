# frozen_string_literal: true

FactoryBot.define do
  factory :raif_prompt_studio_batch_run, class: "Raif::PromptStudioBatchRun" do
    task_type { "Raif::TestTask" }
    llm_model_key { Raif.available_llm_keys.sample.to_s }

    trait :with_judge_binary do
      judge_type { "Raif::Evals::LlmJudges::Binary" }
      judge_config { { "criteria" => "Response is accurate and complete" } }
      judge_llm_model_key { Raif.available_llm_keys.sample.to_s }
    end

    trait :with_judge_scored do
      judge_type { "Raif::Evals::LlmJudges::Scored" }
      judge_config { { "scoring_rubric" => "accuracy" } }
      judge_llm_model_key { Raif.available_llm_keys.sample.to_s }
    end

    trait :completed do
      started_at { 2.minutes.ago }
      completed_at { 1.minute.ago }
      total_count { 3 }
      completed_count { 3 }
    end
  end

  factory :raif_prompt_studio_batch_run_item, class: "Raif::PromptStudioBatchRunItem" do
    association :batch_run, factory: :raif_prompt_studio_batch_run
    association :source_task, factory: [:raif_test_task, :completed]
  end
end
