# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

module Raif
  module Evals
    class Run
      # One eval set's pending execution, paired with the coordinator that dispatches it. The set
      # is read off the coordinator rather than carried alongside, where the two could disagree.
      Unit = Struct.new(:coordinator, :execution, keyword_init: true) do
        def eval_set_class
          coordinator.eval_set_class
        end
      end

      attr_reader :eval_sets, :results, :output, :repeats, :cases, :sample, :seed, :resume_path, :concurrency

      def initialize(file_paths: nil, output: $stdout, repeats: 1, cases: nil, sample: nil, seed: nil, resume_path: nil,
        concurrency: nil)
        @output = output
        @results = {}
        @repeats = [repeats.to_i, 1].max
        @cases = cases.presence
        @resume_path = resume_path.presence
        @sample = sample&.to_i
        @seed = resolve_seed(seed)
        @concurrency = resolve_concurrency(concurrency)
        @reported_eval_sets = Set.new
        @result_order = {}
        @summary_mutex = Mutex.new

        # Before the eval sets, not after: loading an eval set evaluates its class body,
        # so anything setup.rb defines for the sets to use (shared helper modules,
        # scoring rubrics) has to exist by then or the `include` raises NameError.
        load_setup_file

        @eval_sets = if file_paths&.any?
          load_eval_sets_from_files(file_paths)
        else
          discover_eval_sets
        end
      end

      def execute
        output.puts "\nStarting Raif Eval Run"
        output.puts ""
        output.puts "Raif.config.default_llm_model_key: #{Raif.config.default_llm_model_key}"
        output.puts "Raif.config.evals_default_llm_judge_model_key: #{configured_judge_description}"
        output.puts "Repeats per eval: #{repeats}"
        output.puts "Concurrency: #{concurrency}" if concurrency > 1
        output.puts "Cases: #{cases.join(", ")}" if cases
        output.puts "Sample per dataset: #{sample}#{" (seed #{seed})" if seed}" if sample

        if resume_path
          output.puts "Resuming: #{run_log.display_path} (#{run_log.results_count} results already recorded)"
        else
          output.puts "Run log: #{run_log.display_path}"
        end

        print_self_judging_warning if judge_is_model_under_test?

        output.puts ""
        output.puts "=" * 50

        run_eval_sets

        export_results
        print_summary

        # --cases filters every dataset in the run, so an id matching nothing anywhere is a
        # typo. Checked on the case ids that actually ran, not the result count, since the
        # non-dataset evals in the same set run regardless and would make a typo look like a
        # suite that passed. Checked after exporting because those evals already spent
        # inference money, and throwing away their results file is a second loss.
        if cases && dataset_evals_present? && @results.values.flatten.none? { |e| e[:case_id] }
          output.puts Raif::Utils::Colors.red("\nNo eval cases matched --cases #{cases.join(",")}")
          exit 1
        end
      end

    private

      # Results reach the run log as they complete, but the final results file is only written once
      # every set has finished - hence the resume hint, without which a user staring at a stack
      # trace has no way to know the spend is still on disk.
      def run_eval_sets
        units = build_units

        # The CLI defaults to the test environment, where eager_load is off, and concurrent
        # Zeitwerk autoloads are a flake source. Nothing to gain from it on the serial path.
        Rails.application.eager_load! if concurrency > 1

        WorkerPool.new(concurrency: concurrency).run(units) do |unit|
          result = unit.coordinator.run_and_record(unit.execution)
          report_eval_set_progress(unit.eval_set_class)
          result
        end

        # Sets a resumed run had nothing left to do for, which reach no completion callback.
        @eval_set_headers.each_key { |eval_set_class| print_eval_set_summary(eval_set_class) }

        # Includes eval sets the log holds but this invocation did not visit, which is what a
        # resume narrowed to one file leaves behind.
        @results = sorted(run_log.results)
      rescue Interrupt
        print_resume_hint("Run interrupted.")
        exit 1
      rescue StandardError
        print_resume_hint("Run failed.")
        raise
      end

      # One flat list of executions across every eval set, each paired with the instance that
      # coordinates its set - a pool of threads can be handed a flat list. Order is definition
      # order, which is what a serial run executes in and what the eval set summaries follow.
      def build_units
        @pending_by_eval_set = Hash.new(0)
        @result_order = {}

        # Now rather than at construction: the log's header records the dataset fingerprints these
        # coordinators resolve, so the log cannot exist until they do.
        coordinators.each_value { |coordinator| coordinator.run_log = run_log }

        @eval_sets.flat_map do |eval_set_entry|
          eval_set_class, line_number = entry_parts(eval_set_entry)
          coordinator = coordinators.fetch(eval_set_class)

          executions = if line_number
            executions_at_line(coordinator, line_number)
          else
            coordinator.pending_executions(repeats: repeats)
          end

          @pending_by_eval_set[eval_set_class] += executions.count
          # After the executions, so the datasets the ordering is read off have been resolved, and
          # once per eval set rather than once per entry.
          @result_order[eval_set_class.name] ||= coordinator.result_order

          executions.map { |execution| Unit.new(coordinator: coordinator, execution: execution) }
        end
      end

      # One coordinator per eval set, not one per entry: the same file can appear twice on a command
      # line (two line numbers in it, or the same path given twice), and a second coordinator would
      # resolve the set's datasets again.
      #
      # Memoized because building these resolves every dataset in the run, which is both where a bad
      # fixture fails - before the first eval is paid for - and where #dataset_fingerprints comes
      # from, and #configuration_data asks for those before the run log exists.
      def coordinators
        @coordinators ||= build_coordinators
      end

      def build_coordinators
        @eval_set_headers = {}

        @eval_sets.each_with_object({}) do |eval_set_entry, built|
          eval_set_class, line_number = entry_parts(eval_set_entry)
          @eval_set_headers[eval_set_class] ||= eval_set_header(eval_set_class, line_number)

          built[eval_set_class] ||= EvalSetCoordinator.new(
            eval_set_class: eval_set_class,
            output: output,
            writer: writer,
            header: @eval_set_headers[eval_set_class],
            cases: cases,
            sample: sample,
            seed: seed
          )
        end
      end

      # An entry is a hash when the eval sets came from file paths on the command line, and a bare
      # class when they were discovered.
      def entry_parts(eval_set_entry)
        return [eval_set_entry, nil] unless eval_set_entry.is_a?(Hash)

        [eval_set_entry[:class], eval_set_entry[:line_number]]
      end

      # Printed once, when the eval set's first line is ready - or, for a set with nothing to
      # run, when its summary is. Keyed on the set rather than the line, so the two callers
      # cannot print it twice.
      def eval_set_header(eval_set_class, line_number = nil)
        [
          "eval_set:#{eval_set_class.name}",
          "\nRunning #{eval_set_class.name}#{" at line #{line_number}" if line_number}\n#{"-" * 50}"
        ]
      end

      # Called from a worker thread once an execution has been recorded: an eval set is reported
      # as its last execution lands rather than at the end of the run, so a serial run still
      # reports each set as it finishes.
      def report_eval_set_progress(eval_set_class)
        finished = @summary_mutex.synchronize do
          @pending_by_eval_set[eval_set_class] -= 1
          @pending_by_eval_set[eval_set_class].zero?
        end

        print_eval_set_summary(eval_set_class) if finished
      end

      def print_eval_set_summary(eval_set_class)
        return unless @summary_mutex.synchronize { @reported_eval_sets.add?(eval_set_class) }

        # From the log rather than what this invocation returned, so a resumed run reports the
        # whole set and not just the tail of it that was left to do.
        set_results = run_log.results_for(eval_set_class.name)

        # An eval set that produced no output of its own still gets its banner, so the summary
        # line beneath it is attributable. Banner and summary in one call, so another execution
        # finishing at the same moment cannot land between them.
        writer.print_with_headers(
          [@eval_set_headers[eval_set_class] || eval_set_header(eval_set_class)],
          "-" * 50,
          "#{eval_set_class.name}: #{set_results.count { |result| result[:passed] }}/#{set_results.count} evals passed"
        )
      end

      # Buffered only when there is something to interleave with: a serial run's lines appear as
      # they are produced, rather than one execution at a time.
      def writer
        @writer ||= ConsoleWriter.new(output, buffered: concurrency > 1)
      end

      def print_resume_hint(reason)
        output.puts Raif::Utils::Colors.red("\n#{reason}")

        if run_log.results_count.zero?
          run_log.discard!
          return
        end

        output.puts "#{run_log.results_count} results were recorded before it stopped: #{run_log.display_path}"
        output.puts "Resume with: bundle exec raif evals --resume #{run_log.display_path}"
      end

      def run_log
        @run_log ||= build_run_log
      end

      def build_run_log
        if resume_path
          warn_on_code_change
          return RunLog.resume(path: resume_path, configuration: configuration_data)
        end

        run_at = Time.current

        RunLog.start(
          results_dir: Rails.root.join("raif_evals", "results"),
          basename: "eval_run_#{run_at.strftime("%Y%m%d_%H%M%S")}_#{Raif.config.default_llm_model_key}",
          run_at: run_at.iso8601,
          configuration: configuration_data
        )
      rescue RunLog::IncompatibleResumeError => e
        output.puts Raif::Utils::Colors.red("\n#{e.message}")
        exit 1
      end

      # A warning rather than a refusal, unlike everything else the resume check compares: the
      # commit that landed while a run was interrupted is often the one that fixed whatever
      # interrupted it, and refusing would throw away results already paid for. But the results
      # file will name one commit for work produced under two, so it is said out loud.
      def warn_on_code_change
        logged = RunLog.logged_configuration(resume_path)&.dig(:code)
        current = code_provenance
        return if logged.nil? || current.nil?
        return if logged[:git_sha] == current[:git_sha] && logged[:dirty] == current[:dirty]

        output.puts Raif::Utils::Colors.yellow(
          "\nWarning: the code has changed since this run started: #{describe_code(logged)} -> #{describe_code(current)}."
        )
        output.puts Raif::Utils::Colors.yellow(
          "  The results file will record the current one for results produced under both."
        )
      end

      def describe_code(code)
        "#{code[:git_sha].to_s[0, 12]}#{" (dirty)" if code[:dirty]}"
      end

      def load_setup_file
        setup_file = Rails.root.join("raif_evals", "setup.rb")

        if File.exist?(setup_file)
          require setup_file
        else
          output.puts Raif::Utils::Colors.red("\n\nNo setup file found. To set up Raif evals, run:\n")
          output.puts Raif::Utils::Colors.red("bundle exec raif evals:setup\n")
          exit 1
        end
      end

      def load_eval_sets_from_files(file_paths)
        eval_sets = []

        file_paths.each do |f|
          file_path = f[:file_path]
          line_number = f[:line_number]

          absolute_path = File.expand_path(file_path)

          unless File.exist?(absolute_path)
            output.puts Raif::Utils::Colors.red("Error: File not found: #{file_path}")
            exit 1
          end

          subclasses_before = Raif::Evals::EvalSet.subclasses

          require absolute_path

          # require is a no-op for an already-loaded file (auto-discovery, or the same path
          # given twice), so the subclass diff can be empty for a perfectly valid file.
          loaded_eval_sets = Raif::Evals::EvalSet.subclasses - subclasses_before
          eval_set_class = loaded_eval_sets.first || eval_set_class_defined_in(absolute_path)

          eval_set_entry = { class: eval_set_class, file_path: absolute_path }
          eval_set_entry[:line_number] = line_number if line_number

          eval_sets << eval_set_entry
        end

        eval_sets
      end

      # Keyed off evals that actually use `dataset:`, not sets that merely declare one: a
      # declared-but-unconsumed dataset must not make --cases look like it matched nothing.
      def dataset_evals_present?
        @eval_sets.any? do |eval_set_entry|
          eval_set_class = eval_set_entry.is_a?(Hash) ? eval_set_entry[:class] : eval_set_entry
          eval_set_class.evals.any?(&:dataset?)
        end
      end

      def eval_set_class_defined_in(absolute_path)
        Raif::Evals::EvalSet.subclasses.find do |klass|
          klass.evals.any? { |eval_definition| eval_definition.file == absolute_path }
        end
      end

      def executions_at_line(coordinator, line_number)
        target_eval = coordinator.eval_set_class.evals.find{|e| e.line_number == line_number }

        if target_eval.nil?
          output.puts Raif::Utils::Colors.red("Error: No eval block found at line #{line_number}")
          return []
        end

        coordinator.executions_for(target_eval, repeats: repeats)
      end

      def discover_eval_sets
        eval_sets_dir = Rails.root.join("raif_evals", "eval_sets")
        return [] unless eval_sets_dir.exist?

        Dir.glob(eval_sets_dir.join("**", "*_eval_set.rb")).map do |file|
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          require Rails.root.join(relative_path)

          path_from_eval_sets = Pathname.new(file).relative_path_from(eval_sets_dir)
          path_parts = path_from_eval_sets.dirname.to_s.split("/")

          # "." is what dirname gives for a file sitting directly in eval_sets.
          path_parts = [] if path_parts == ["."]

          class_name = File.basename(file, ".rb").camelize
          namespace_parts = ["Raif", "Evals"] + path_parts.map(&:camelize)
          full_class_name = (namespace_parts + [class_name]).join("::")

          full_class_name.constantize
        end.select { |klass| klass < Raif::Evals::EvalSet }
      end

      # The model key goes in both the filename and the payload: comparing models means
      # holding several result files side by side, and a run that only names its model in
      # stdout cannot be attributed back to one once the terminal is gone. The timestamp is when
      # the run started, so a resume completes the file its first attempt was headed for.
      def export_results
        filename = run_log.results_path
        FileUtils.mkdir_p(File.dirname(filename))

        File.write(filename, JSON.pretty_generate({
          run_at: run_log.run_at,
          configuration: configuration_data,
          results: @results,
          summary: summary_data
        }))

        # Only once the durable file exists, since until then the log is the only copy.
        run_log.discard!

        output.puts "\nResults exported to: #{filename}"
      end

      # Results reach the log in completion order, which under concurrency is neither definition
      # order nor stable between runs. Put back into definition order once, here, rather than
      # only on the way to the file: the summary groups results as it finds them, so the per-case
      # rows of two runs of the same work would otherwise be ordered differently too.
      #
      # Results whose eval set this invocation never visited - what a resume narrowed to one file
      # carries forward - have no known position, so they keep the order the log holds them in.
      def sorted(results)
        results.to_h do |eval_set_name, eval_results|
          order = @result_order[eval_set_name] || {}

          ordered = eval_results.each_with_index.sort_by do |result, index|
            [
              result[:eval_index].to_i,
              order.fetch([result[:eval_index], result[:case_id]], Float::INFINITY),
              result[:run_index].to_i,
              index
            ]
          end

          [eval_set_name, ordered.map(&:first)]
        end
      end

      def judge_model_key
        Raif::Evals::LlmJudge.resolved_llm_model_key
      end

      # Named rather than left blank in the header: an unset judge key does not mean nothing judged,
      # it means the model under test did.
      def configured_judge_description
        return Raif.config.evals_default_llm_judge_model_key if Raif.config.evals_default_llm_judge_model_key.present?

        "(not set - judged by #{judge_model_key}, the model under test)"
      end

      def judge_is_model_under_test?
        judge_model_key.to_s == Raif.config.default_llm_model_key.to_s
      end

      # Before the first eval rather than in the summary, so it is read before the run is paid for.
      # Not conditional on the run actually judging anything: whether an eval reaches a judge helper
      # is only known once its block has run.
      def print_self_judging_warning
        output.puts ""
        output.puts Raif::Utils::Colors.yellow(
          "Warning: any LLM judge expectation in this run will be graded by #{judge_model_key}, the model under test."
        )
        output.puts Raif::Utils::Colors.yellow(
          "  A model grading its own output is subject to self-preference bias, and running this again against a " \
          "different model\n  moves the ruler along with the thing being measured. Set " \
          "Raif.config.evals_default_llm_judge_model_key (or\n  RAIF_EVALS_DEFAULT_LLM_JUDGE_MODEL_KEY) to hold the " \
          "judge fixed across runs, ideally to a model from outside\n  the family under test."
        )
      end

      # sqlite3 is capped rather than rejected: an eval runs inside a transaction, and concurrent
      # write transactions against one file serialize on SQLITE_BUSY instead of going faster.
      #
      # The pool check is a hard failure because the alternative is worse than a slow run: with
      # fewer connections than workers, each execution waits out the checkout timeout and dies
      # with ConnectionTimeoutError, which reads like a database problem rather than a setting.
      def resolve_concurrency(concurrency)
        requested = [(concurrency || Raif.config.evals_concurrency).to_i, 1].max
        return 1 if requested == 1

        adapter = ActiveRecord::Base.connection_db_config.adapter.to_s

        if adapter.start_with?("sqlite")
          output.puts Raif::Utils::Colors.yellow(
            "Ignoring concurrency #{requested}: the #{adapter} adapter serializes the transaction each eval runs in. Running serially."
          )
          return 1
        end

        pool_size = ActiveRecord::Base.connection_pool.size

        if pool_size <= requested
          output.puts Raif::Utils::Colors.red(
            "Concurrency #{requested} needs a database connection pool larger than #{requested}, but this environment's pool holds " \
            "#{pool_size}. Raise `pool:` for the #{Rails.env} environment in config/database.yml, or lower --concurrency."
          )
          exit 1
        end

        requested
      end

      # A sampled run always ends up with a seed, drawing one when the caller did not supply it.
      # Without one the draw is fresh entropy every invocation, so --resume would sample a
      # different subset and finish the results file with two unrelated samples in it - which
      # #configuration_data cannot catch, since both invocations record `seed: nil` and compare
      # equal. A resume therefore adopts the seed the log holds rather than drawing again, which
      # would be refused as a mismatch the user has no way to satisfy. Small enough to retype
      # from the console banner.
      def resolve_seed(seed)
        return seed&.to_i if seed || @sample.nil?

        resumed_seed || Random.new.rand(2**31)
      end

      def resumed_seed
        return unless resume_path

        RunLog.logged_configuration(resume_path)&.dig(:seed)
      end

      # Also the compatibility check for --resume, which refuses when any of these differ: each
      # either changes what a result means or which cases produce one, so letting one drift
      # would write a single results file describing a run that never happened.
      #
      # Concurrency is deliberately absent: it changes neither, and including it would refuse to
      # resume a run at a different concurrency, which is exactly what someone whose run just
      # died to rate limits wants to do.
      def configuration_data
        {
          default_llm_model_key: Raif.config.default_llm_model_key,
          evals_default_llm_judge_model_key: Raif.config.evals_default_llm_judge_model_key,
          # The model that actually graded, which is what has to match for two runs to be
          # comparable. The setting above is null for every run that configured no judge, so two
          # models judged by themselves would compare as though one ruler had graded both.
          judge_model_key: judge_model_key,
          repeats: repeats,
          capture_model_completions: Raif.config.evals_capture_model_completions.to_s,
          cases: cases,
          sample: sample,
          seed: seed,
          # What was actually measured, so an edited case cannot read as a model regression - see
          # Raif::Evals::Dataset#digest. Compared entry by entry on resume, over the datasets both
          # sides resolved, since a resume narrowed to one eval set file knows only about that
          # file's datasets.
          datasets: dataset_fingerprints,
          # Provenance rather than compatibility, which is why Raif::Evals::RunLog leaves it out of
          # the resume check - see #warn_on_code_change. Null rather than absent when there is no
          # git checkout to read, like the keys above it: a reader can then tell a run that recorded
          # nothing from one written before there was anything to record.
          code: code_provenance
        }
      end

      # Sorted, so two runs of the same suite record their datasets in the same order however the
      # eval set files were discovered or listed.
      def dataset_fingerprints
        @dataset_fingerprints ||= coordinators
          .each_value
          .flat_map(&:dataset_fingerprints)
          .sort_by { |fingerprint| [fingerprint[:eval_set].to_s, fingerprint[:name]] }
      end

      # The host app's HEAD, so a reader can tell which side of a prompt change a run was on -
      # comparing one model before and after a code change is one of the two workflows
      # evals:compare exists for, and nothing else in the results records that.
      #
      # nil when the host app is not a git checkout, or git is not installed: a results file
      # without this is still worth having, and no eval run should die over `git`.
      def code_provenance
        return @code_provenance if defined?(@code_provenance)

        sha = git("rev-parse", "HEAD")
        @code_provenance = sha && { git_sha: sha, dirty: git("status", "--porcelain").present? }
      end

      def git(*args)
        stdout, _stderr, status = Open3.capture3("git", "-C", Rails.root.to_s, *args)
        stdout.strip.presence if status.success?
      rescue StandardError
        nil
      end

      # One row per distinct eval, collapsing its repeats into a pass rate - the comparable
      # number between models, since a single pass/fail cannot separate a real quality
      # difference from one unlucky sample. Grouped by eval id rather than description, which two
      # eval blocks can share, or they would report one blended rate.
      #
      # A dataset eval also reports a rate per case, since a model can improve on average
      # while getting worse on one input. Non-dataset rows keep their existing keys.
      def eval_pass_rates
        grouped_evals.map do |eval_set_name, runs|
          next pass_rate_row(eval_set_name, runs) unless runs.any? { |e| e[:case_id] }

          per_case = runs.group_by { |e| e[:case_id] }.map do |case_id, case_runs|
            tally(case_runs).merge(case_id: case_id)
          end

          pass_rate_row(eval_set_name, runs).merge(
            eval_index: runs.first[:eval_index],
            cases: per_case.count,
            repeats: repeats,
            per_case: per_case
          )
        end
      end

      # One row per score name per eval. This is the number that ranks two models, and
      # stddev and ci95 sit next to it so a mean cannot be over-read: two models a tenth of
      # a point apart with a spread of half a point have not been distinguished.
      def score_summaries
        grouped_evals.flat_map do |eval_set_name, runs|
          entries = runs.flat_map do |e|
            (e[:scores] || []).map { |score| score.merge(case_id: e[:case_id]) }
          end

          entries.group_by { |score| score[:name] }.map do |name, scores|
            values = scores.map { |score| score[:value] }
            per_case = score_per_case(scores)
            # Unrounded, since resampling the rounded values per_case reports for display
            # would quantize the interval bounds.
            #
            # stddev and ci95 are both over this, not over the pooled values the mean comes from.
            # Pooling mixes differences between inputs with repeat-to-repeat noise on one input,
            # and on a dataset of any breadth the first dominates - so it measures how varied the
            # dataset is, where a reader beside a mean needs how uncertain the mean is.
            spread_sample = per_case ? per_case_means(scores) : values
            ci95 = Statistics.bootstrap_ci95(spread_sample)&.map { |bound| round(bound) }

            {
              eval_set: eval_set_name,
              description: runs.first[:description],
              eval_id: runs.first[:eval_id],
              eval_index: runs.first[:eval_index],
              name: name,
              scale: scores.first[:scale],
              higher_is_better: scores.first[:higher_is_better],
              n: values.count,
              # What stddev and ci95 are over, which is not n for a dataset eval: 20 cases at
              # --repeat 3 is n: 60, spread_n: 20. Without it the two figures look like they
              # describe the 60.
              spread_n: spread_sample.count,
              mean: round(Statistics.mean(values)),
              median: round(Statistics.median(values)),
              stddev: round(Statistics.stddev(spread_sample)),
              min: values.min,
              max: values.max,
              ci95: ci95,
              # Said rather than left out. An absent interval and an interval too small a sample
              # to compute read identically in a summary, and only the second tells a reader what
              # to do about it.
              ci95_omitted: (ci95_omission(spread_sample, per_case) if ci95.nil?),
              per_case: per_case
            }.compact
          end
        end
      end

      # In the unit the spread was measured in - cases for a dataset eval, runs otherwise - since
      # that is what a reader would have to add more of to get an interval.
      def ci95_omission(spread_sample, per_case)
        unit = per_case ? "case" : "run"

        "#{spread_sample.count} #{unit.pluralize(spread_sample.count)}; a 95% interval needs #{Statistics::MIN_BOOTSTRAP_SAMPLE}"
      end

      def grouped_evals
        @results.flat_map do |eval_set_name, evals|
          evals.group_by { |e| e[:eval_id] }.map { |_key, runs| [eval_set_name, runs] }
        end
      end

      def pass_rate_row(eval_set_name, runs)
        {
          eval_set: eval_set_name,
          description: runs.first[:description],
          eval_id: runs.first[:eval_id]
        }.merge(tally(runs))
      end

      # Errored runs leave the denominator rather than counting as failures. An error measured
      # nothing, so scoring it as a miss lets a provider incident masquerade as a quality drop -
      # and pass rates are what evals:compare gates on.
      #
      # errored is always emitted, unlike the per-result key: a reader of the rate needs the
      # denominator it was taken over, and an absent key cannot be told from a zero.
      def tally(runs)
        errored = runs.count { |e| e[:errored] }
        passed = runs.count { |e| e[:passed] }

        { runs: runs.count, errored: errored, passed: passed, pass_rate: rate(passed, runs.count - errored) }
      end

      def score_per_case(scores)
        return unless scores.any? { |score| score[:case_id] }

        scores.group_by { |score| score[:case_id] }.map do |case_id, case_scores|
          case_values = case_scores.map { |score| score[:value] }
          { case_id: case_id, n: case_values.count, mean: round(Statistics.mean(case_values)) }
        end
      end

      def per_case_means(scores)
        scores.group_by { |score| score[:case_id] }.map do |_case_id, case_scores|
          Statistics.mean(case_scores.map { |score| score[:value] })
        end
      end

      # nil, not 0.0, when every run errored: the evals produced no measurement, and a zero would
      # claim they all failed. Consumers read it the way evals:compare reads an unmatched case -
      # as nothing to compare rather than as a result.
      def rate(passed, measured)
        return if measured.zero?

        (passed.to_f / measured).round(4)
      end

      def round(value)
        value&.round(4)
      end

      # Memoized: both export_results and print_summary ask for it, and score_summaries runs a
      # 1000-resample bootstrap per score row.
      def summary_data
        @summary_data ||= build_summary_data
      end

      def build_summary_data
        total_eval_sets = @results.count
        total_evals = @results.values.sum(&:count)
        passed_evals = @results.values.sum { |evals| evals.count { |e| e[:passed] } }

        total_expectations = @results.values.sum do |evals|
          evals.sum { |e| e[:expectation_results].count }
        end

        passed_expectations = @results.values.sum do |evals|
          evals.sum { |e| e[:expectation_results].count { |r| r[:status] == :passed } }
        end

        # Counted separately at both levels so "failed" means what it says. Without these the
        # only way back to the error count is to re-derive it from every expectation's status,
        # which is exactly the work a summary exists to have already done.
        errored_evals = @results.values.sum { |evals| evals.count { |e| e[:errored] } }

        errored_expectations = @results.values.sum do |evals|
          evals.sum { |e| e[:expectation_results].count { |r| r[:status] == :error } }
        end

        all_evals = @results.values.flatten
        total_model_completions = all_evals.sum { |e| e.dig(:usage, :model_completions).to_i }
        total_prompt_tokens = all_evals.sum { |e| e.dig(:usage, :prompt_tokens).to_i }
        total_completion_tokens = all_evals.sum { |e| e.dig(:usage, :completion_tokens).to_i }
        total_tokens = all_evals.sum { |e| e.dig(:usage, :total_tokens).to_i }
        total_cost = all_evals.sum { |e| e.dig(:usage, :total_cost).to_f }.round(6)

        # What setup and teardown spent. Beside the eval totals rather than folded into them,
        # since evals:compare reads total_cost across runs recorded by earlier versions - but
        # real money, so a summary that dropped it would understate the bill.
        overhead_model_completions = all_evals.sum { |e| e.dig(:overhead_usage, :model_completions).to_i }
        overhead_tokens = all_evals.sum { |e| e.dig(:overhead_usage, :total_tokens).to_i }
        overhead_cost = all_evals.sum { |e| e.dig(:overhead_usage, :total_cost).to_f }.round(6)

        # The judge's share of the totals above, not spend beside them. Reported apart because the
        # judge is held fixed across a comparison, so a cost delta that is really the judge reading
        # a wordier model tells a reader nothing about the model's own price - see
        # Raif::Evals::EvalResult#judge_completion?.
        judge_model_completions = all_evals.sum { |e| e.dig(:judge_usage, :model_completions).to_i }
        judge_tokens = all_evals.sum { |e| e.dig(:judge_usage, :total_tokens).to_i }
        judge_cost = all_evals.sum { |e| e.dig(:judge_usage, :total_cost).to_f }.round(6)

        {
          total_eval_sets: total_eval_sets,
          total_evals: total_evals,
          passed_evals: passed_evals,
          errored_evals: errored_evals,
          total_expectations: total_expectations,
          passed_expectations: passed_expectations,
          errored_expectations: errored_expectations,
          total_model_completions: total_model_completions,
          total_prompt_tokens: total_prompt_tokens,
          total_completion_tokens: total_completion_tokens,
          total_tokens: total_tokens,
          total_cost: total_cost,
          total_overhead_model_completions: overhead_model_completions,
          total_overhead_tokens: overhead_tokens,
          total_overhead_cost: overhead_cost,
          total_judge_model_completions: judge_model_completions,
          total_judge_tokens: judge_tokens,
          total_judge_cost: judge_cost,
          eval_pass_rates: eval_pass_rates,
          score_summaries: score_summaries
        }
      end

      def print_summary
        data = summary_data

        output.puts ""
        output.puts "\n" + "=" * 50
        output.puts "SUMMARY"
        output.puts "=" * 50
        output.puts "Model: #{Raif.config.default_llm_model_key}"
        output.puts "Judge: #{judge_model_key}#{" (the model under test)" if judge_is_model_under_test?}"
        output.puts "Eval Sets: #{data[:total_eval_sets]}"
        output.puts ""
        output.puts "Evals:"
        print_outcome_counts(data[:total_evals], data[:passed_evals], data[:errored_evals])
        output.puts ""
        output.puts "Expectations:"
        print_outcome_counts(data[:total_expectations], data[:passed_expectations], data[:errored_expectations])
        output.puts ""
        output.puts "LLM Usage:"
        output.puts "  #{data[:total_model_completions]} LLM calls"
        output.puts "  #{data[:total_prompt_tokens]} prompt tokens"
        output.puts "  #{data[:total_completion_tokens]} completion tokens"
        output.puts "  #{data[:total_tokens]} total tokens"
        output.puts "  $#{format("%.6f", data[:total_cost])} total cost"
        print_judge_cost(data)

        if data[:total_overhead_model_completions].positive?
          calls = data[:total_overhead_model_completions]
          output.puts "  plus #{calls} #{"call".pluralize(calls)} / " \
            "$#{format("%.6f", data[:total_overhead_cost])} in setup and teardown, not attributed to any eval"
        end

        output.puts ""

        # A dataset eval has a rate worth printing even at --repeat 1, because the rate is
        # then over inputs rather than over repeats of one input.
        if repeats > 1 || data[:eval_pass_rates].any? { |row| row[:per_case] }
          output.puts "Pass rates:"
          data[:eval_pass_rates].each do |row|
            output.puts "  #{colorized_rate(row)} #{row[:eval_set]}: #{row[:description]}"

            row[:per_case]&.each do |per_case|
              output.puts "    #{colorized_rate(per_case)} #{per_case[:case_id]}"
            end
          end
          output.puts ""
        end

        if data[:score_summaries].any?
          output.puts "Scores:"
          data[:score_summaries].each do |row|
            spread = ["n #{row[:n]}"]
            # Named only when it differs from n, which is the dataset case: sd and ci95 are over
            # the per-case means, so "n 60" beside them would overstate what they were measured on.
            spread << "over #{row[:spread_n]} cases" if row[:spread_n] && row[:spread_n] != row[:n]
            spread << "sd #{row[:stddev]}" if row[:stddev]
            spread << "ci95 [#{row[:ci95].join(", ")}]" if row[:ci95]
            spread << "ci95 omitted: #{row[:ci95_omitted]}" if row[:ci95_omitted]

            output.puts "  #{row[:name]}: mean #{row[:mean]} (#{spread.join(", ")}) #{row[:eval_set]}: #{row[:description]}"

            row[:per_case]&.each do |per_case|
              output.puts "    #{per_case[:mean]} #{per_case[:case_id]} (n #{per_case[:n]})"
            end
          end
          output.puts ""
        end
      end

      # Indented under the total rather than added to it: these two are that total split, and the
      # split is the number to read when comparing two models, since the judge is meant to be the
      # same on both sides. Printed only when a judge ran.
      def print_judge_cost(data)
        calls = data[:total_judge_model_completions].to_i
        return unless calls.positive?

        subject_cost = (data[:total_cost] - data[:total_judge_cost]).round(6)
        output.puts "    $#{format("%.6f", subject_cost)} model under test"
        output.puts "    $#{format("%.6f", data[:total_judge_cost])} judge (#{calls} #{"call".pluralize(calls)})"
      end

      # Errored is its own line rather than folded into failed, and printed only when there is
      # one: a "0 errored" on every clean run is noise, and the count is what tells a reader the
      # rates below were taken over fewer runs than they asked for.
      def print_outcome_counts(total, passed, errored)
        output.puts "  #{total} total"
        output.puts Raif::Utils::Colors.green("  #{passed} passed")
        output.puts Raif::Utils::Colors.red("  #{total - passed - errored.to_i} failed")
        output.puts Raif::Utils::Colors.yellow("  #{errored} errored") if errored.to_i.positive?
      end

      def colorized_rate(row)
        errored = row[:errored].to_i
        measured = row[:runs] - errored

        # Yellow rather than red: nothing was measured, so there is no verdict to report.
        return Raif::Utils::Colors.yellow("#{errored}/#{row[:runs]} errored") if row[:pass_rate].nil?

        rate = "#{row[:passed]}/#{measured} (#{(row[:pass_rate] * 100).round}%)"
        colorize = if row[:pass_rate] == 1.0
          :green
        elsif row[:pass_rate].zero?
          :red
        else
          :yellow
        end

        line = Raif::Utils::Colors.public_send(colorize, rate)
        line += Raif::Utils::Colors.yellow("  +#{errored} errored") if errored.positive?
        line
      end
    end
  end
end
