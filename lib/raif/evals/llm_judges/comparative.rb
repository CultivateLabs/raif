# frozen_string_literal: true

module Raif
  module Evals
    module LlmJudges
      class Comparative < Raif::Evals::LlmJudge
        task_run_arg :over_content # the content to compare against
        task_run_arg :comparison_criteria # the criteria to use when comparing content_to_judge to over_content
        task_run_arg :allow_ties # whether to allow ties in the comparison

        attr_accessor :content_a, :content_b, :expected_winner

        before_create do
          self.expected_winner = ["A", "B"].sample

          if expected_winner == "A"
            self.content_a = content_to_judge
            self.content_b = over_content
          else
            self.content_a = over_content
            self.content_b = content_to_judge
          end
        end

        json_response_schema do
          string :winner, description: "Which content is better (A, B, or tie)", enum: ["A", "B", "tie"]
          string :reasoning, description: "Detailed explanation of the judgment"
          number :confidence, description: "Confidence level from 0.0 to 1.0", minimum: 0, maximum: 1
        end

        def build_system_prompt
          <<~PROMPT.strip
            You are an expert evaluator comparing two pieces of content to determine which better meets specified criteria.

            #{allow_ties ? "You may declare a tie if both pieces of content are equally good." : "You must choose a winner even if the difference is minimal."}

            First, provide detailed reasoning for your choice. Then, provide a precise winner #{allow_ties ? "(A, B, or tie)" : "(A or B)"}.

            Respond with JSON matching the required schema.
          PROMPT
        end

        def build_prompt
          <<~PROMPT.strip
            Comparison criteria: #{comparison_criteria}
            #{additional_context_prompt}
            Compare the following two pieces of content:

            CONTENT A:
            #{content_a}

            CONTENT B:
            #{content_b}

            Which content better meets the comparison criteria?
          PROMPT
        end

        def winner
          parsed_response["winner"] if completed?
        end

        def tie?
          return unless completed? # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

          parsed_response["winner"] == "tie"
        end

        def correct_expected_winner?
          return unless completed? # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

          parsed_response["winner"] == expected_winner
        end

      private

        def additional_context_prompt
          return if additional_context.blank?

          <<~PROMPT

            Additional context:
            #{additional_context}
          PROMPT
        end
      end
    end
  end
end
