# frozen_string_literal: true

module Raif
  module Evals
    class LlmJudge < Raif::Task
      # Set default temperature for consistent judging
      llm_temperature 0.0

      # Default to JSON response format for structured output
      llm_response_format :json

      task_run_arg :content_to_judge # the content to judge
      task_run_arg :additional_context # additional context to be provided to the judge

      def default_llm_model_key
        Raif.config.evals_default_llm_judge_model_key || super
      end

      def judgment_reasoning
        parsed_response["reasoning"] if completed?
      end

      def judgment_confidence
        parsed_response["confidence"] if completed?
      end

      def low_confidence?
        judgment_confidence && judgment_confidence < 0.5
      end
    end
  end
end
