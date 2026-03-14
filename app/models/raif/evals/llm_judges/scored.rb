# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_tasks
#
#  id                     :bigint           not null, primary key
#  available_model_tools  :jsonb            not null
#  completed_at           :datetime
#  creator_type           :string
#  failed_at              :datetime
#  llm_model_key          :string           not null
#  prompt                 :text
#  prompt_studio_run      :boolean          default(FALSE), not null
#  raw_response           :text
#  requested_language_key :string
#  response_format        :integer          default("text"), not null
#  run_with               :jsonb
#  source_type            :string
#  started_at             :datetime
#  system_prompt          :text
#  type                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  creator_id             :bigint
#  source_id              :bigint
#
# Indexes
#
#  index_raif_tasks_on_completed_at           (completed_at)
#  index_raif_tasks_on_created_at             (created_at)
#  index_raif_tasks_on_creator                (creator_type,creator_id)
#  index_raif_tasks_on_failed_at              (failed_at)
#  index_raif_tasks_on_source                 (source_type,source_id)
#  index_raif_tasks_on_started_at             (started_at)
#  index_raif_tasks_on_type                   (type)
#  index_raif_tasks_on_type_and_completed_at  (type,completed_at)
#  index_raif_tasks_on_type_and_failed_at     (type,failed_at)
#  index_raif_tasks_on_type_and_started_at    (type,started_at)
#
module Raif
  module Evals
    module LlmJudges
      class Scored < Raif::Evals::LlmJudge
        run_with :scoring_rubric # the scoring rubric to use when evaluating the content

        json_response_schema do
          number :score, description: "Numerical score based on the rubric"
          string :reasoning, description: "Detailed explanation of the score"
          number :confidence, description: "Confidence level from 0.0 to 1.0", minimum: 0, maximum: 1
        end

        def build_system_prompt
          <<~PROMPT.strip
            You are an expert evaluator providing numerical scores based on a detailed rubric.

            First, provide detailed reasoning/explanation of your evaluation. Then, provide a precise score according to the provided rubric.

            Respond with JSON matching this schema:
            {
              "score": number,
              "reasoning": "detailed explanation",
              "confidence": 0.0-1.0
            }
          PROMPT
        end

        def build_prompt
          <<~PROMPT.strip
            Scoring rubric:
            #{format_rubric(scoring_rubric)}
            #{additional_context_prompt}
            Evaluate the following content according to the scoring rubric:
            #{content_to_judge}

            Provide your score and detailed reasoning.
          PROMPT
        end

        def judgment_score
          parsed_response["score"] if completed?
        end

      private

        def additional_context_prompt
          return if additional_context.blank?

          <<~PROMPT
            \nAdditional context:
            #{additional_context}
          PROMPT
        end

        def format_rubric(rubric)
          rubric.is_a?(ScoringRubric) ? rubric.to_prompt : rubric.to_s
        end
      end
    end
  end
end
