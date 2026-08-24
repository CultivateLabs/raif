# frozen_string_literal: true

module Raif
  module Evals
    # Everything one eval set needs to run that is not the running of an eval: resolving its
    # datasets, listing the executions it still owes, and dispatching them.
    #
    # Not an EvalSet, because an EvalSet instance is single-use by construction: #run_eval writes
    # the case and result onto it so #expect and #score can reach them. One of these is long-lived
    # per eval set, and holds the collaborators shared across the whole run.
    class EvalSetCoordinator
      attr_reader :eval_set_class, :output, :writer, :header, :cases, :sample, :seed

      # Assignable because Raif::Evals::Run builds its coordinators before its run log: the log's
      # header records dataset fingerprints only a resolved coordinator can produce.
      attr_accessor :run_log

      # @param eval_set_class [Class] the Raif::Evals::EvalSet subclass being run.
      # @param writer [Raif::Evals::ConsoleWriter, nil] serializes this set's output with
      #   whatever else is writing to the same console. Defaults to an unbuffered writer of its
      #   own, which is what a host app calling EvalSet.run directly gets.
      # @param header [Array(Object, String), nil] a [key, line] pair the writer prints once,
      #   before this eval set's first line. Raif::Evals::Run uses it for the eval set banner.
      # @param cases [Array<String>, nil] restrict every dataset to these case ids (--cases).
      # @param sample [Integer, nil] draw this many cases from each dataset (--sample).
      # @param seed [Integer, nil] the seed that draw uses (--seed). These three scope the whole
      #   coordinator rather than any one call to it - see #selected_cases.
      def initialize(eval_set_class:, output: $stdout, run_log: nil, writer: nil, header: nil, cases: nil, sample: nil, seed: nil)
        @eval_set_class = eval_set_class
        @output = output
        @run_log = run_log
        @writer = writer || ConsoleWriter.new(output)
        @header = header
        @cases = cases
        @sample = sample
        @seed = seed
      end

      # Runs everything this set still owes, in definition order. The path a host app calling
      # EvalSet.run takes; Raif::Evals::Run instead collects #pending_executions across every
      # set and dispatches them itself.
      def run(repeats: 1)
        pending_executions(repeats: repeats).map do |execution|
          run_and_record(execution)
        end
      end

      # Every execution this eval set still owes, across all of its evals, without running any of
      # them. Listing them rather than running them is what lets Raif::Evals::Run build one work
      # list across every set.
      def pending_executions(repeats: 1)
        eval_set_class.evals.flat_map do |eval_definition|
          executions_for(eval_definition, repeats: repeats)
        end
      end

      # Every execution key this eval set covers, whether or not the run log already holds a result
      # for it: the plan, where #executions_for is whatever is left of it. Deliberately blind to
      # the log, since this is what the log is started with, before there is one to consult.
      #
      # @param eval_definitions [Array<Raif::Evals::EvalDefinition>, nil] restrict the plan to
      #   these evals, which is what a file path given with a line number does.
      def planned_keys(eval_definitions: nil, repeats: 1)
        (eval_definitions || eval_set_class.evals).flat_map do |eval_definition|
          eval_cases = selected_cases_for(eval_definition) || [nil]

          eval_cases.flat_map do |eval_case|
            repeat_run_indexes(repeats).map do |run_index|
              RunLog.key(eval_id: eval_definition.id, case_id: eval_case&.id, run_index: run_index)
            end
          end
        end
      end

      # The pending executions of one eval definition, in dataset order then repeat order.
      def executions_for(eval_definition, repeats: 1)
        eval_cases = selected_cases_for(eval_definition)
        eval_id = eval_definition.id
        run_indexes = repeat_run_indexes(repeats)

        if eval_cases.nil?
          return run_indexes.filter_map do |run_index|
            next if already_recorded?(eval_id, nil, run_index)

            Execution.new(eval_definition: eval_definition, run_index: run_index)
          end
        end

        # Widened over every selected case, not just the pending ones, so a resumed run's lines
        # stay aligned with the ones already printed.
        case_id_width = eval_cases.map { |eval_case| eval_case.id.length }.max

        eval_cases.flat_map do |eval_case|
          run_indexes.filter_map do |run_index|
            next if already_recorded?(eval_id, eval_case.id, run_index)

            Execution.new(
              eval_definition: eval_definition,
              eval_case: eval_case,
              run_index: run_index,
              case_id_width: case_id_width
            )
          end
        end
      end

      # What this eval set's datasets held, for the run's configuration block. One entry per
      # dataset, naming it, how many cases it has, and a digest of their contents - see
      # Raif::Evals::Dataset#digest.
      def dataset_fingerprints
        datasets.map do |name, dataset|
          selected = selected_cases[name].count

          {
            eval_set: eval_set_class.name,
            name: name.to_s,
            cases: dataset.size,
            digest: dataset.digest,
            # Only when a selection narrowed the dataset, so a full run does not repeat `cases` in
            # every entry.
            selected: (selected unless selected == dataset.size)
          }.compact
        end
      end

      # Where each [eval_index, case_id] pair sits in this set's definition order, for putting
      # results that completed in another order back into it. Keyed on every selected case, so a
      # resumed run orders the results it inherited too. A position rather than the case id, since
      # sorting on the id would replace the dataset author's order with alphabetical order.
      def result_order
        eval_set_class.evals.flat_map do |eval_definition|
          eval_cases = selected_cases_for(eval_definition) || [nil]
          eval_cases.map.with_index { |eval_case, position| [[eval_definition.index, eval_case&.id], position] }
        end.to_h
      end

      # Runs one execution and records its result. The unit of work Raif::Evals::Run hands to a
      # worker thread, so everything it touches has to be safe to call concurrently: the run log
      # takes a lock, and console output goes through a writer that flushes as one block.
      def run_and_record(execution)
        eval_result = nil

        writer.capture(headers: headers_for(execution)) do |execution_output|
          # A fresh eval set per execution: run_eval writes the current case and result onto the
          # instance, so a shared one would allow only one execution in flight.
          eval_result = eval_set_class.new(output: execution_output).run_eval(
            execution.eval_definition,
            eval_case: execution.eval_case,
            run_index: execution.run_index,
            case_id_width: execution.case_id_width
          )

          # Recorded the moment it completes, so the run's spend survives an interrupt that
          # never reaches the results file.
          run_log&.record(eval_set: eval_set_class.name, result: eval_result)
        end

        eval_result
      end

    private

      # nil rather than 1 for a single run, matching the run_index EvalResult records.
      def repeat_run_indexes(repeats)
        repeats.times.map { |i| (i + 1 if repeats > 1) }
      end

      # The eval set banner, then the eval's own description, each printed once when the first
      # result underneath it lands - under concurrency results arrive in completion order, so there
      # is no earlier point at which a header is known to describe what follows it. Only the compact
      # one-line-per-case output needs one: verbose output names the eval on every line.
      def headers_for(execution)
        eval_header = if execution.eval_case && !Raif.config.evals_verbose_output
          ["eval:#{execution.eval_id}", execution.eval_definition.description]
        end

        [header, eval_header]
      end

      def already_recorded?(eval_id, case_id, run_index)
        return false if run_log.nil?

        run_log.recorded?(eval_id: eval_id, case_id: case_id, run_index: run_index)
      end

      # Resolved and validated before the first eval executes, so a missing fixture or a duplicated
      # case id fails before any inference is paid for. Through an eval set instance because a
      # dataset block is user DSL: file/files/json/jsonl only exist there.
      def resolve_datasets
        names = eval_set_class.evals.filter_map(&:dataset).uniq
        return {} if names.empty?

        dataset_context = eval_set_class.new(output: output)

        names.to_h { |name| [name, Dataset.new(name: name, cases: dataset_context.resolve_dataset(name))] }
      end

      # The whole of each dataset, which is what #dataset_fingerprints is taken over. Memoized
      # because resolving is where a dataset block runs and a fixture is read.
      def datasets
        @datasets ||= resolve_datasets
      end

      # Memoized separately from #datasets: drawing a sample must not happen twice for one eval set,
      # since an unseeded --sample would draw differently the second time.
      def selected_cases
        @selected_cases ||= datasets.transform_values do |dataset|
          dataset.select_cases(ids: cases, sample: sample, seed: seed)
        end
      end

      def selected_cases_for(eval_definition)
        name = eval_definition.dataset
        return if name.nil?

        selected_cases[name] || []
      end
    end
  end
end
