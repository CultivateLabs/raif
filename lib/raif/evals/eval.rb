# frozen_string_literal: true

module Raif
  module Evals
    class Eval
      attr_reader :description, :expectation_results, :model_completions, :run_index, :eval_index

      # eval_index identifies which eval block produced this result. Descriptions are not
      # unique - the DSL does not enforce it - so it is the only stable way to tell two
      # same-named eval blocks apart when collapsing repeats into a pass rate.
      def initialize(description:, run_index: nil, eval_index: nil)
        @description = description
        @run_index = run_index
        @eval_index = eval_index
        @expectation_results = []
        @model_completions = []
      end

      def add_expectation_result(result)
        @expectation_results << result
      end

      # Records the Raif::ModelCompletion records that were created while this eval ran.
      # These are captured before the eval's transaction is rolled back, so we serialize
      # them into plain hashes that can be exported to the results JSON.
      def record_model_completions(completions)
        @model_completions = Array(completions).map { |mc| serialize_model_completion(mc) }
      end

      def passed?
        expectation_results.all?(&:passed?)
      end

      def usage
        {
          model_completions: model_completions.count,
          prompt_tokens: sum_metric(:prompt_tokens),
          completion_tokens: sum_metric(:completion_tokens),
          total_tokens: sum_metric(:total_tokens),
          total_cost: sum_cost(:total_cost)
        }
      end

      def to_h
        {
          description: description,
          eval_index: eval_index,
          run_index: run_index,
          passed: passed?,
          expectation_results: expectation_results.map(&:to_h),
          usage: usage,
          model_completions: model_completions
        }.compact
      end

    private

      def sum_metric(key)
        model_completions.sum { |mc| mc[key].to_i }
      end

      def sum_cost(key)
        model_completions.sum { |mc| mc[key].to_f }.round(6)
      end

      def serialize_model_completion(mc)
        {
          llm_model_key: mc.llm_model_key,
          model_api_name: mc.model_api_name,
          source_type: mc.source_type,
          temperature: mc.temperature&.to_f,
          response_format: mc.response_format,
          system_prompt: mc.system_prompt,
          messages: mc.messages,
          response: mc.raw_response,
          response_array: mc.response_array.presence,
          response_tool_calls: mc.response_tool_calls.presence,
          response_finish_reason: mc.response_finish_reason,
          prompt_tokens: mc.prompt_tokens,
          completion_tokens: mc.completion_tokens,
          total_tokens: mc.total_tokens,
          cache_creation_input_tokens: mc.cache_creation_input_tokens,
          cache_read_input_tokens: mc.cache_read_input_tokens,
          prompt_token_cost: mc.prompt_token_cost&.to_f,
          output_token_cost: mc.output_token_cost&.to_f,
          total_cost: mc.total_cost&.to_f,
          retry_count: mc.retry_count,
          started_at: mc.started_at&.iso8601,
          completed_at: mc.completed_at&.iso8601
        }.compact
      end
    end
  end
end
