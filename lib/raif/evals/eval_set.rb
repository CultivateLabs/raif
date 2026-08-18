# frozen_string_literal: true

require "raif/evals/eval_sets/expectations"
require "raif/evals/eval_sets/llm_judge_expectations"
require "raif/evals/eval_sets/matchers"

module Raif
  module Evals
    # A host app's eval sets subclass this: the class body is the DSL (eval, dataset, setup,
    # teardown) and an instance is the context those blocks are evaluated against.
    #
    # An instance is single-use: #run_eval writes the case and result onto self so #expect and
    # #score can reach them. Deciding what to run and dispatching it is EvalSetCoordinator's.
    class EvalSet
      include Raif::Evals::EvalSets::Expectations
      include Raif::Evals::EvalSets::Matchers
      include Raif::Evals::EvalSets::LlmJudgeExpectations

      attr_reader :current_eval_result, :current_case, :output

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
        #
        # @param id [String, Symbol, nil] Overrides the description-derived half of the eval's
        #   id - see Raif::Evals::EvalDefinition#id. Pass one when you expect to reword the
        #   description without wanting the reworded eval treated as a new one.
        def eval(description, dataset: nil, id: nil, &block)
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

          declared_id = validated_eval_id(id, description)
          check_eval_identity!(description, declared_id)

          definition_location = caller_locations(1, 1).first

          # Position assigned here rather than derived later: evals is append-only, so the
          # index a definition registers at is the one it keeps.
          evals << EvalDefinition.new(
            description: description,
            block: block,
            dataset: dataset&.to_sym,
            index: evals.length,
            eval_set_class: self,
            declared_id: declared_id,
            file: definition_location.path,
            line_number: definition_location.lineno
          )
        end

        def setup(&block)
          @setup_block = block
        end

        def teardown(&block)
          @teardown_block = block
        end

        # Runs the whole set and returns one EvalResult per execution. The entry point for a
        # host app running an eval set on its own; Raif::Evals::Run drives the coordinator
        # directly so it can interleave several sets.
        def run(output: $stdout, repeats: 1, cases: nil, sample: nil, seed: nil, run_log: nil)
          EvalSetCoordinator
            .new(eval_set_class: self, output: output, run_log: run_log, cases: cases, sample: sample, seed: seed)
            .run(repeats: repeats)
        end

      private

        # An id ends up in the results JSON, in the run log, and on a command line, so it is held to
        # what is safe in all three rather than to anything Ruby accepts as a string.
        def validated_eval_id(id, description)
          return if id.nil?

          id = id.to_s

          unless id.match?(/\A[A-Za-z0-9_.:-]+\z/)
            raise ArgumentError, "eval #{description.inspect} was given id #{id.inspect}, which is not a valid eval id. Use " \
              "letters, numbers, and any of _ . : -"
          end

          id
        end

        # Checked here rather than when an id is first derived, so a mistake costs a load error
        # instead of a run's worth of inference. On descriptions rather than ids because a derived id
        # is a digest of one, so two evals collide exactly when their descriptions do.
        def check_eval_identity!(description, declared_id)
          if declared_id && evals.any? { |definition| definition.declared_id == declared_id }
            raise ArgumentError, "eval #{description.inspect} declares id #{declared_id.inspect}, which another eval in " \
              "#{name || "this eval set"} already declares. An id identifies one eval across runs, so it has to be unique " \
              "within the set."
          end

          duplicate = evals.find { |definition| definition.description == description }
          return if duplicate.nil?

          # Two evals with one description derive one id, so their results would be joined as
          # though they came from the same eval.
          if declared_id.nil? && duplicate.declared_id.nil?
            raise ArgumentError, "#{name || "this eval set"} already has an eval described as #{description.inspect}, and an " \
              "eval's identity is derived from its description. Reword one of them, or give one an explicit id:."
          end
        end
      end

      # Attributes every LLM judge this eval set runs needs. Override when the host app has
      # extended Raif::Task with a column the judge task cannot be inserted without. Called
      # per eval, after setup, so it can reference what setup created.
      def judge_task_attributes
        {}
      end

      # Evaluates one of the set's dataset blocks. Here rather than on the coordinator because
      # a dataset block is user DSL - it can call file/files/json/jsonl, which only exist on an
      # eval set instance.
      def resolve_dataset(name)
        instance_eval(&self.class.datasets.fetch(name))
      end

      # Runs one execution - one eval block, against one case, on one repeat. Writes the current
      # case and result onto this instance, which is why each execution gets its own.
      def run_eval(eval_definition, eval_case: nil, run_index: nil, case_id_width: nil)
        @current_case = eval_case
        @case_id_width = case_id_width
        @current_eval_result = EvalResult.new(
          description: eval_definition.description,
          eval_id: eval_definition.id,
          run_index: run_index,
          eval_index: eval_definition.index,
          case_id: eval_case&.id
        )

        compact = compact_output?
        if compact
          # The compact line reports counts that only exist once the case has run, so
          # per-expectation output is discarded rather than printed. Errors still go to
          # console_output - a swallowed backtrace makes a dataset run undebuggable.
          @output = StringIO.new
        else
          output.puts "Running: #{eval_definition.description}#{" [#{eval_case.id}]" if eval_case}#{" (run #{run_index})" if run_index}"
        end

        begin
          ActiveRecord::Base.transaction do
            # Opened before setup and closed after teardown, so nothing an execution spends
            # escapes the run's cost total. Which of those calls the eval itself made is
            # decided by the offsets taken around the eval block, not by the sink's lifetime.
            completions = ModelCompletionSink.open
            eval_completions_range = nil

            begin
              # A setup that raised leaves the eval block nothing to run against, so it is
              # skipped rather than run against a half-built fixture and billed for it.
              if setup_succeeded?(eval_case)
                eval_completions_start = completions.length
                run_stage("Eval block") { run_block(eval_definition.block, eval_case) }
                eval_completions_range = eval_completions_start...completions.length
              end
            ensure
              run_stage("Teardown") { run_block(self.class.teardown_block, eval_case) } if self.class.teardown_block

              # Closed first, so a capture failure cannot leave the sink open. Capturing after
              # teardown is safe because the sink holds the records rather than re-querying them,
              # so a teardown that destroys them cannot take them with it.
              ModelCompletionSink.close
              capture_model_completions(completions, eval_completions_range)
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

        unless full_path.to_s.start_with?(base_path.to_s)
          raise ArgumentError, "Invalid filename: path traversal detected"
        end

        full_path
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
        # Three outcomes, not two: an eval that raised did not fail, it did not run, and a red
        # ✗ next to it sends the reader looking for a quality problem that is not there.
        symbol, color = if result.errored?
          ["!", :yellow]
        elsif result.passed?
          ["✓", :green]
        else
          ["✗", :red]
        end

        parts = ["  #{symbol} #{result.case_id.ljust(@case_id_width.to_i)}"]
        parts << "run #{result.run_index}" if result.run_index
        parts << "#{result.expectation_results.count(&:passed?)}/#{result.expectation_results.count} expectations"
        parts << result.scores.map { |score| "#{score.name} #{score.formatted_value}" }.join("  ") if result.scores.any?

        console_output.puts Raif::Utils::Colors.public_send(color, parts.join("  "))

        result.expectation_results.reject(&:passed?).each do |expectation_result|
          description = ConsoleLine.truncate_description(expectation_result.description)
          console_output.puts Raif::Utils::Colors.red("      ✗ #{description}")
        end
      end

      # Runs one stage of an execution inside its own rescue, returning whether it got through. An
      # escaping raise would abort the run - under concurrency, every execution in flight with it -
      # and the result this one already paid for would never reach the run log.
      def run_stage(stage)
        yield
        true
      rescue => e
        console_output.puts Raif::Utils::Colors.red("  Error in #{stage.downcase}: #{e.message}")
        console_output.puts Raif::Utils::Colors.red("  #{e.backtrace.join("\n  ")}")
        @current_eval_result.add_expectation_result(
          ExpectationResult.new(description: "#{stage} execution", status: :error, error: e)
        )
        false
      end

      def setup_succeeded?(eval_case)
        return true if self.class.setup_block.nil?

        run_stage("Setup") { run_block(self.class.setup_block, eval_case) }
      end

      # Splits what the sink collected into the eval block's own calls and the ones setup and
      # teardown made around it - only the former is the eval's usage, but both are real spend.
      # Wrapped defensively so a capture failure never fails the eval itself.
      def capture_model_completions(completions, eval_completions_range)
        eval_completions = eval_completions_range ? completions[eval_completions_range] : []
        # By position rather than by set difference: Array#- compares model completions by id,
        # which two unsaved records would collide on.
        overhead = completions.reject.with_index { |_completion, index| eval_completions_range&.cover?(index) }

        @current_eval_result.record_model_completions(
          eval_completions,
          overhead: overhead,
          capture_mode: Raif.config.evals_capture_model_completions
        )
      rescue => e
        console_output.puts Raif::Utils::Colors.red("  Error capturing model completions: #{e.message}")
      end
    end
  end
end
