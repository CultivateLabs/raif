# frozen_string_literal: true

module Raif
  module Evals
    module LlmJudges
      class Binary < Raif::Evals::LlmJudge
        run_with :criteria
        run_with :examples
        run_with :strict_mode

        json_response_schema do
          boolean :passes, description: "Whether the content passes the criteria"
          string :reasoning, description: "Detailed explanation of the judgment"
          number :confidence, description: "Confidence level from 0.0 to 1.0", minimum: 0, maximum: 1
        end

        def build_system_prompt
          <<~PROMPT.strip
            You are an expert evaluator assessing whether content meets specific criteria.
            Your task is to make binary pass/fail judgments with clear reasoning.

            First, provide detailed reasoning/explanation of your evaluation. Then, provide a precise pass/fail judgment.

            Respond with JSON matching this schema:
            {
              "passes": boolean,
              "reasoning": "detailed explanation",
              "confidence": 0.0-1.0
            }
          PROMPT
        end

        def build_prompt
          prompt = <<~PROMPT
            Evaluation criteria: #{criteria}

            #{strict_mode ? "Apply the criteria strictly without any leniency." : "Apply reasonable judgment while adhering to the criteria."}
          PROMPT

          if examples.present?
            prompt += "\nHere are examples of how to evaluate:"
            examples.each do |example|
              prompt += format_example(example)
            end
          end

          prompt += additional_context_prompt if additional_context.present?

          prompt += <<~PROMPT.rstrip

            Now evaluate this content:
            #{content_to_judge}

            Does this content meet the evaluation criteria?
          PROMPT

          prompt
        end

        # Judgment accessor methods
        def passes?
          parsed_response["passes"] if completed?
        end

      private

        def additional_context_prompt
          <<~PROMPT

            Additional context:
            #{additional_context}
          PROMPT
        end

        def format_example(example)
          if example.key?(:output)
            content_label = "Output"
            content_value = example[:output]
          else
            content_label = "Content"
            content_value = example[:content]
          end

          <<~EXAMPLE

            #{content_label}: #{content_value}
            Reasoning: #{example[:reasoning]}
            Judgment: #{example[:passes] ? "PASS" : "FAIL"}
          EXAMPLE
        end
      end
    end
  end
end
