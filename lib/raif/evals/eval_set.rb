# frozen_string_literal: true

require "raif/evals/eval_sets/expectations"
require "raif/evals/eval_sets/llm_judge_expectations"

module Raif
  module Evals
    class EvalSet
      include Raif::Evals::EvalSets::Expectations
      include Raif::Evals::EvalSets::LlmJudgeExpectations

      attr_reader :current_eval_result, :current_case, :output, :results

      def initialize(output: $stdout)
        @output = output
        @console_output = output
      end

      class << self
        attr_reader :setup_block
        attr_reader :teardown_block

        def inherited(subclass)
          subclass.instance_variable_set(:@evals, [])
          subclass.instance_variable_set(:@datasets, {})
          super
        end

        def evals
          @evals ||= []
        end

        def datasets
          @datasets ||= {}
        end

        # Registers a named collection of eval cases. The block is not run here: it is
        # resolved at run time in instance context so it can use file/files/json/jsonl.
        def dataset(name, &block)
          raise ArgumentError, "dataset #{name.inspect} requires a block" unless block

          datasets[name.to_sym] = block
        end

        # This shadows Kernel#eval inside the class body. Without the block check, a
        # block-less call - what reaching for Kernel#eval looks like here - would register an
        # eval that fails only once it runs, after setup has spent inference money.
        def eval(description, dataset: nil, &block)
          raise ArgumentError, "eval #{description.inspect} requires a block" unless block

          # A registered name and nothing else: an inline array or Proc would be a dataset
          # with no name, and the name is what a case id is reported against.
          if dataset && !dataset.is_a?(Symbol) && !dataset.is_a?(String)
            raise ArgumentError, "eval #{description.inspect} passed #{dataset.class} to dataset:, which takes the name of a " \
              "dataset declared with the `dataset` macro."
          end

          if dataset && !datasets.key?(dataset.to_sym)
            raise ArgumentError, "eval #{description.inspect} names dataset #{dataset.inspect}, which has not been declared. " \
              "Declare it above the evals that use it#{" (declared: #{datasets.keys.inspect})" if datasets.any?}."
          end

          definition_location = caller_locations(1, 1).first

          evals << {
            description: description,
            block: block,
            dataset: dataset&.to_sym,
            definition_file: definition_location.path,
            definition_line_number: definition_location.lineno
          }
        end

        def setup(&block)
          @setup_block = block
        end

        def teardown(&block)
          @teardown_block = block
        end

        def run(output: $stdout, repeats: 1, cases: nil, sample: nil, seed: nil)
          new(output: output).run(repeats: repeats, cases: cases, sample: sample, seed: seed)
        end
      end

      # Attributes every LLM judge this eval set runs needs. Override when the host app has
      # extended Raif::Task with a column the judge task cannot be inserted without. Called
      # per eval, after setup, so it can reference what setup created.
      def judge_task_attributes
        {}
      end

      # Each repeat re-runs setup and the eval block from scratch, so the repeats are
      # independent samples of a non-deterministic model rather than a re-scoring of one
      # response. Comparing models needs the pass rate across them, not a single draw.
      #
      # An eval with a dataset runs once per case per repeat, each in its own transaction.
      def run(repeats: 1, cases: nil, sample: nil, seed: nil)
        @results = []
        @selected_cases = resolve_datasets(cases: cases, sample: sample, seed: seed)

        self.class.evals.each_with_index do |eval_definition, eval_index|
          @results.concat(run_eval_definition(eval_definition, eval_index: eval_index, repeats: repeats))
        end

        @results
      end

      # Runs one eval definition across its cases (if any) and repeats.
      def run_eval_definition(eval_definition, eval_index: nil, repeats: 1, cases: nil, sample: nil, seed: nil)
        eval_index ||= self.class.evals.index(eval_definition)
        @selected_cases ||= resolve_datasets(cases: cases, sample: sample, seed: seed)
        eval_cases = selected_cases_for(eval_definition)

        if eval_cases.nil?
          return repeats.times.map do |i|
            run_eval(eval_definition, run_index: (i + 1 if repeats > 1), eval_index: eval_index)
          end
        end

        return [] if eval_cases.empty?

        output.puts eval_definition[:description] unless Raif.config.evals_verbose_output
        @case_id_width = eval_cases.map { |eval_case| eval_case.id.length }.max

        eval_cases.flat_map do |eval_case|
          repeats.times.map do |i|
            run_eval(eval_definition, eval_case: eval_case, run_index: (i + 1 if repeats > 1), eval_index: eval_index)
          end
        end
      end

      def run_eval(eval_definition, eval_case: nil, run_index: nil, eval_index: nil)
        @current_case = eval_case
        @current_eval_result = EvalResult.new(
          description: eval_definition[:description],
          run_index: run_index,
          eval_index: eval_index || self.class.evals.index(eval_definition),
          case_id: eval_case&.id
        )

        compact = compact_output?
        if compact
          # The compact line reports counts that only exist once the case has run, so
          # per-expectation output is discarded rather than printed. Errors still go to
          # console_output - a swallowed backtrace makes a dataset run undebuggable.
          @output = StringIO.new
        else
          output.puts "Running: #{eval_definition[:description]}#{" [#{eval_case.id}]" if eval_case}#{" (run #{run_index})" if run_index}"
        end

        begin
          ActiveRecord::Base.transaction do
            # setup runs inside the same rescue as the eval block so that one case built
            # from a bad fixture costs one result rather than the whole dataset.
            stage = "Setup"
            model_completions_start_id = nil

            begin
              run_block(self.class.setup_block, eval_case) if self.class.setup_block

              stage = "Eval block"
              # After setup, so we only record the LLM calls the eval itself makes.
              model_completions_start_id = Raif::ModelCompletion.maximum(:id) || 0

              run_block(eval_definition[:block], eval_case)
            rescue => e
              console_output.puts Raif::Utils::Colors.red("  Error in #{stage.downcase}: #{e.message}")
              console_output.puts Raif::Utils::Colors.red("  #{e.backtrace.join("\n  ")}")
              @current_eval_result.add_expectation_result(
                ExpectationResult.new(
                  description: "#{stage} execution",
                  status: :error,
                  error: e
                )
              )
            ensure
              # Before teardown: sources like Raif::Agent declare `has_many
              # :raif_model_completions, dependent: :destroy`, so a teardown that destroys
              # them takes the rows we need with it.
              capture_model_completions(model_completions_start_id) if model_completions_start_id

              run_block(self.class.teardown_block, eval_case) if self.class.teardown_block
            end

            raise ActiveRecord::Rollback
          end
        ensure
          @output = console_output
        end

        print_case_summary if compact

        @current_eval_result
      end

      def file(filename)
        path = evals_path("files", filename)

        raise ArgumentError, "File #{filename} does not exist in raif_evals/files/" unless path.exist?

        path.read
      end

      # Returns paths relative to raif_evals/files, so they compose with #file rather than
      # having to be turned back into relative paths by the caller.
      def files(glob)
        base_path = evals_dir("files")

        Dir.glob(evals_path("files", glob).to_s).sort.select { |path| File.file?(path) }.map do |path|
          Pathname.new(path).relative_path_from(base_path).to_s
        end
      end

      # One JSON case object per line, from raif_evals/datasets.
      def jsonl(filename)
        dataset_file(filename).each_line.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
      end

      # A JSON array of case objects, from raif_evals/datasets.
      def json(filename)
        JSON.parse(dataset_file(filename))
      end

    private

      attr_reader :console_output

      def dataset_file(filename)
        path = evals_path("datasets", filename)

        raise ArgumentError, "File #{filename} does not exist in raif_evals/datasets/" unless path.exist?

        path.read
      end

      def evals_dir(dir)
        Rails.root.join("raif_evals", dir)
      end

      def evals_path(dir, filename)
        raise ArgumentError, "Invalid filename: cannot be empty" if filename.nil? || filename.empty?
        raise ArgumentError, "Invalid filename: cannot contain '..' or absolute paths" if filename.include?("..") || filename.start_with?("/")

        base_path = evals_dir(dir)
        full_path = base_path.join(filename)

        # Verify the resolved path is within the expected directory
        unless full_path.to_s.start_with?(base_path.to_s)
          raise ArgumentError, "Invalid filename: path traversal detected"
        end

        full_path
      end

      # Every dataset the run will touch is resolved and validated before the first eval
      # executes, so a missing or duplicated case id fails before any inference is paid for.
      def resolve_datasets(cases: nil, sample: nil, seed: nil)
        names = self.class.evals.filter_map { |eval_definition| eval_definition[:dataset] }.uniq

        names.to_h do |name|
          dataset = Dataset.new(name: name, cases: instance_eval(&self.class.datasets[name]))
          [name, dataset.select_cases(ids: cases, sample: sample, seed: seed)]
        end
      end

      def selected_cases_for(eval_definition)
        name = eval_definition[:dataset]
        return if name.nil?

        @selected_cases[name] || []
      end

      # Existing 0-arity setup and eval blocks keep going through instance_eval untouched;
      # only a block that asks for the case is handed one.
      def run_block(block, eval_case)
        block.arity.zero? ? instance_eval(&block) : instance_exec(eval_case, &block)
      end

      def compact_output?
        !@current_case.nil? && !Raif.config.evals_verbose_output
      end

      # One line per case per repeat, in place of the several hundred expectation lines a
      # 20-case dataset at --repeat 3 would otherwise bury the failures in.
      def print_case_summary
        result = @current_eval_result
        color = result.passed? ? :green : :red

        parts = ["  #{result.passed? ? "✓" : "✗"} #{result.case_id.ljust(@case_id_width.to_i)}"]
        parts << "run #{result.run_index}" if result.run_index
        parts << "#{result.expectation_results.count(&:passed?)}/#{result.expectation_results.count} expectations"
        parts << result.scores.map { |score| "#{score.name} #{score.formatted_value}" }.join("  ") if result.scores.any?

        console_output.puts Raif::Utils::Colors.public_send(color, parts.join("  "))

        result.expectation_results.reject(&:passed?).each do |expectation_result|
          description = ConsoleLine.truncate_description(expectation_result.description)
          console_output.puts Raif::Utils::Colors.red("      ✗ #{description}")
        end
      end

      # Records the model completions created during the eval (those with an id greater
      # than the baseline captured before the eval ran) onto the current eval so they can
      # be exported. Wrapped defensively so a capture failure never fails the eval itself.
      def capture_model_completions(start_id)
        completions = Raif::ModelCompletion.where("id > ?", start_id).order(:id).to_a
        @current_eval_result.record_model_completions(completions, capture_mode: Raif.config.evals_capture_model_completions)
      rescue => e
        console_output.puts Raif::Utils::Colors.red("  Error capturing model completions: #{e.message}")
      end

    end
  end
end
