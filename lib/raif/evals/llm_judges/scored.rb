# frozen_string_literal: true

module Raif
  module Evals
    module LlmJudges
      class Scored < Raif::Evals::LlmJudge
        task_run_arg :scoring_rubric # the scoring rubric to use when evaluating the content

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
