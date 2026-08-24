# frozen_string_literal: true

module Raif
  module Evals
    # The outcome of one execution of an eval block, not the eval block itself. The block and
    # its description live on an EvalDefinition; running one against one EvalCase produces one
    # of these.
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

      attr_reader :description, :eval_id, :expectation_results, :model_completions, :run_index, :eval_index, :case_id, :scores, :usage,
        :overhead_usage, :judge_usage

      # eval_id identifies the eval block that produced this result and survives the file being
      # edited around it; with case_id, the dataset input, it is the key evals:compare and --resume
      # match on. eval_index is that eval's position, which orders results within one run.
      def initialize(description:, eval_id: nil, run_index: nil, eval_index: nil, case_id: nil)
        @description = description
        @eval_id = eval_id
        @run_index = run_index
        @eval_index = eval_index
        @case_id = case_id
        @expectation_results = []
        @model_completions = []
        @scores = []
        @usage = EMPTY_USAGE.dup
        @overhead_usage = EMPTY_USAGE.dup
        @judge_usage = EMPTY_USAGE.dup
        # Seeded from the configured mode, so a result that never reaches
        # #record_model_completions - one built directly by a spec or a host app's own helper -
        # omits the key under :none like its siblings instead of carrying an empty array.
        @model_completions_captured = capture_mode_records_completions?
      end

      def add_expectation_result(result)
        @expectation_results << result
      end

      # A score name is a metric the run summary aggregates by. Recording the same name twice
      # for one eval would blend them into one row, hiding a regression in one behind an
      # improvement in the other and narrowing the confidence interval on correlated values.
      def add_score(score_result)
        ensure_score_name_available!(score_result.name)

        @scores << score_result
      end

      # Public so a caller about to spend money producing the value can ask first, as
      # expect_llm_judge_score does: discovering the collision on the way back costs a request.
      def ensure_score_name_available!(name)
        return unless @scores.any? { |score| score.name == name.to_s }

        raise ArgumentError, "score #{name.to_s.inspect} was already recorded for this eval. Give the two scores distinct " \
          "names (expect_llm_judge_score takes score_name:), or combine the values yourself and record one score."
      end

      # Serialized into plain hashes here because the eval's transaction is about to be rolled back
      # and the rows with it.
      #
      # overhead is what setup and teardown spent. Kept out of #usage, which is the eval's own
      # measurement, but summed so the run's cost total is not short of what the run cost. Usage
      # only: the prompt and response of a call that built a fixture is not worth exporting.
      def record_model_completions(completions, overhead: [], capture_mode: :full)
        serialized = Array(completions).map { |mc| serialize_model_completion(mc) }
        @usage = compute_usage(serialized)
        @overhead_usage = compute_usage(Array(overhead).map { |mc| serialize_model_completion(mc) })
        # A subset of #usage rather than a slice taken out of it: the eval did spend this, so the
        # run's cost total must keep counting it. The split is for the comparison.
        @judge_usage = compute_usage(serialized.select { |mc| mc[:judge] })
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

      # An error is a missing measurement, not a bad one: a 429, a socket timeout, or a raise in
      # setup says nothing about the quality of the model's output. Kept distinct from a failure
      # all the way through aggregation, so a rate-limited afternoon does not read as a regression.
      def errored?
        expectation_results.any?(&:error?)
      end

      def to_h
        {
          description: description,
          eval_id: eval_id,
          eval_index: eval_index,
          run_index: run_index,
          case_id: case_id,
          passed: passed?,
          # Omitted when false, for the reason overhead_usage is omitted when empty.
          errored: (true if errored?),
          expectation_results: expectation_results.map(&:to_h),
          scores: (scores.map(&:to_h) if scores.any?),
          usage: usage,
          # Omitted rather than zeroed: setup making no LLM calls is the normal case, and the key
          # would be noise in every result those runs wrote.
          overhead_usage: (overhead_usage if overhead_usage[:model_completions].positive?),
          # Omitted for the same reason, and for the same reason an absent key is not a zero: a
          # result written before the judge was tagged has unknown judge spend, not none.
          judge_usage: (judge_usage if judge_usage[:model_completions].positive?),
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

      # An LLM judge grades on the same terms across a comparison by design - evals:compare refuses
      # two different judges - so its spend should not be read as part of the difference between two
      # models. Not quite constant, since a wordier model gives the judge more to read.
      #
      # Read off the in-memory source rather than source_type, which holds "Raif::Task" for every
      # task: source_type is the polymorphic base class and a judge is an STI subclass of it.
      # Defensive, since a source that cannot be resolved is not a reason to fail an eval.
      def judge_completion?(mc)
        mc.source.is_a?(Raif::Evals::LlmJudge)
      rescue StandardError
        false
      end

      def serialize_model_completion(mc)
        {
          llm_model_key: mc.llm_model_key,
          model_api_name: mc.model_api_name,
          source_type: mc.source_type,
          judge: (true if judge_completion?(mc)),
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
