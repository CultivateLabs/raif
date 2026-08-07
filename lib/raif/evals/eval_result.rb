# frozen_string_literal: true

module Raif
  module Evals
    # The outcome of one execution of an eval block, not the eval block itself. The block and
    # its description live in EvalSet.evals; running it against one EvalCase produces one of
    # these.
    class EvalResult
      # The text :summary capture drops. Tokens and cost survive in every mode, so the usage
      # totals never depend on capture mode.
      COMPLETION_TEXT_KEYS = [:system_prompt, :messages, :response, :response_array, :response_tool_calls].freeze

      EMPTY_USAGE = {
        model_completions: 0,
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
        total_cost: 0.0
      }.freeze

      attr_reader :description, :expectation_results, :model_completions, :run_index, :eval_index, :case_id, :scores, :usage

      # eval_index identifies which eval block produced this result; descriptions are not
      # unique, so it is the only stable way to tell two same-named eval blocks apart when
      # collapsing repeats into a pass rate. case_id is the dataset input it ran against, and
      # is the join key evals:compare matches on.
      def initialize(description:, run_index: nil, eval_index: nil, case_id: nil)
        @description = description
        @run_index = run_index
        @eval_index = eval_index
        @case_id = case_id
        @expectation_results = []
        @model_completions = []
        @scores = []
        @usage = EMPTY_USAGE.dup
        # Seeded from the configured mode, so an eval that never reached
        # #record_model_completions - one whose setup raised - omits the key under :none like
        # its siblings instead of being the one result carrying an empty array.
        @model_completions_captured = capture_mode_records_completions?
      end

      def add_expectation_result(result)
        @expectation_results << result
      end

      # A score name is a metric the run summary aggregates by. Recording the same name twice
      # for one eval would blend them into one row, hiding a regression in one behind an
      # improvement in the other and narrowing the confidence interval on correlated values.
      def add_score(score_result)
        if @scores.any? { |score| score.name == score_result.name }
          raise ArgumentError, "score #{score_result.name.inspect} was already recorded for this eval. Give the two scores distinct " \
            "names (expect_llm_judge_score takes score_name:), or combine the values yourself and record one score."
        end

        @scores << score_result
      end

      # Records the Raif::ModelCompletion records that were created while this eval ran.
      # These are captured before the eval's transaction is rolled back, so we serialize
      # them into plain hashes that can be exported to the results JSON.
      def record_model_completions(completions, capture_mode: :full)
        serialized = Array(completions).map { |mc| serialize_model_completion(mc) }
        @usage = compute_usage(serialized)
        @model_completions_captured = capture_mode.to_sym != :none

        @model_completions = case capture_mode.to_sym
        when :none
          []
        when :summary
          serialized.map { |mc| mc.except(*COMPLETION_TEXT_KEYS) }
        else
          serialized
        end
      end

      def passed?
        expectation_results.all?(&:passed?)
      end

      def to_h
        {
          description: description,
          eval_index: eval_index,
          run_index: run_index,
          case_id: case_id,
          passed: passed?,
          expectation_results: expectation_results.map(&:to_h),
          scores: (scores.map(&:to_h) if scores.any?),
          usage: usage,
          model_completions: (model_completions if @model_completions_captured)
        }.compact
      end

    private

      # Read defensively: this class is constructed in specs and by host apps that may not have
      # gone through Raif.configure, and a missing config is not a reason to fail an eval.
      def capture_mode_records_completions?
        Raif.config.evals_capture_model_completions.to_s != "none"
      rescue StandardError
        true
      end

      def compute_usage(serialized)
        {
          model_completions: serialized.count,
          prompt_tokens: sum_metric(serialized, :prompt_tokens),
          completion_tokens: sum_metric(serialized, :completion_tokens),
          total_tokens: sum_metric(serialized, :total_tokens),
          total_cost: sum_cost(serialized, :total_cost)
        }
      end

      def sum_metric(serialized, key)
        serialized.sum { |mc| mc[key].to_i }
      end

      def sum_cost(serialized, key)
        serialized.sum { |mc| mc[key].to_f }.round(6)
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
