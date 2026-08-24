# frozen_string_literal: true

require "fileutils"
require "json"

module Raif
  module Evals
    # An append-only JSON Lines log of a run: a header line carrying the run's identity and the
    # plan it set out to execute, then one line per eval result as that result completes.
    #
    # A run's results file is only written once every eval set has finished, so without this a
    # run killed partway through would lose every result it had already paid for.
    # `raif evals --resume` reads the log back so that work is not bought twice.
    #
    # The plan is what makes the log the authority on whether the run is done - see
    # Raif::Evals::RunPlan. Without it a resume could only ask itself, and an invocation narrowed
    # to one eval set file would answer yes while most of the run was still outstanding.
    class RunLog
      PARTIAL_SUFFIX = ".partial.jsonl"

      # Raised when a resume would mix results that do not belong in one file together.
      class IncompatibleResumeError < StandardError; end

      # Configuration keys the log records to describe the run rather than to constrain a resume.
      # The code the run started against is one: insisting on it would strand the results of any run
      # interrupted across a commit. Raif::Evals::Run warns when it moved instead.
      PROVENANCE_KEYS = ["code"].freeze

      # Compared specially - see .dataset_differences.
      DATASETS_KEY = "datasets"

      attr_reader :path, :run_at, :configuration, :plan, :results

      def initialize(path:, run_at:, configuration:, plan:, results: {}, recorded_keys: nil)
        @path = Pathname.new(path.to_s)
        @run_at = run_at
        @configuration = configuration
        @plan = plan
        @results = results
        @recorded_keys = recorded_keys || Set.new
        # Concurrent evals record into one log. The append is one File.open per LLM-bound eval,
        # so serializing the whole of #record costs nothing next to what produced the result.
        @mutex = Mutex.new
      end

      class << self
        # Starts a fresh log and writes its header, so a run that dies before its first result
        # still leaves a file that identifies what was being run and what it owes.
        def start(results_dir:, basename:, run_at:, configuration:, plan:)
          FileUtils.mkdir_p(results_dir)

          log = new(
            path: File.join(results_dir, "#{basename}#{PARTIAL_SUFFIX}"),
            run_at: run_at,
            configuration: configuration,
            plan: plan
          )

          # Truncating, unlike every write after it: a stale log left at the same path by an
          # abandoned run of the same second would otherwise gain a second header.
          log.send(:write_header, { type: "run", run_at: run_at, plan: plan.to_h, configuration: configuration })
          log
        end

        # Reopens an interrupted run's log. The whole configuration has to match - see
        # Run#configuration_data.
        #
        # @param plan [Raif::Evals::RunPlan] what the resuming invocation itself covers, which for
        #   a resume narrowed to one file is a fraction of the run. Reconciled against the logged
        #   plan rather than replacing it - see #extend_plan!.
        def resume(path:, configuration:, plan:)
          log = read(path)
          header = log[:header]

          if header.nil?
            raise IncompatibleResumeError, "#{path} has no run header line, so it is not a Raif eval run log."
          end

          if log[:unidentified_results].positive?
            raise IncompatibleResumeError, "Refusing to resume #{path}: #{log[:unidentified_results]} of its results were written " \
              "before evals had ids, so there is no way to tell which of this run's executions they cover. Start a new run."
          end

          logged_plan = read_plan(path, log[:plan_records])

          differences = configuration_differences(header[:configuration], configuration)
          unless differences.empty?
            raise IncompatibleResumeError, <<~MSG.strip
              Refusing to resume #{path}: this run was started with different settings.

              #{differences.join("\n")}

              Re-run with the settings the log was started with, or drop --resume to start a new run.
            MSG
          end

          run_log = new(
            path: path,
            run_at: header[:run_at],
            configuration: configuration,
            plan: logged_plan,
            results: log[:results],
            recorded_keys: log[:recorded_keys]
          )

          run_log.extend_plan!(plan)
          run_log
        end

        # The configuration a log was started with, read without opening it for writing. A resumed
        # run needs one value out of it - the seed - before it can state its own configuration.
        # Returns nil for anything that is not a readable log; #resume is what reports on that.
        def logged_configuration(path)
          header = read(path)[:header]
          header && header[:configuration]
        rescue SystemCallError
          nil
        end

      private

        # Every plan record in the log, folded into one. Unreadable rather than absent is its own
        # refusal: a log written before plans existed, or under a version this code cannot read,
        # is one whose outstanding work cannot be told from its finished work.
        def read_plan(path, plan_records)
          if plan_records.empty?
            raise IncompatibleResumeError, "Refusing to resume #{path}: it records no run plan, so there is no way to tell " \
              "which of this run's executions are still outstanding. Start a new run."
          end

          plans = plan_records.map do |record|
            RunPlan.from_h(record) || raise(IncompatibleResumeError,
              "Refusing to resume #{path}: its run plan was written in a format this version of Raif cannot read " \
              "(expected version #{RunPlan::VERSION}). Start a new run.")
          end

          plans.reduce { |merged, plan| merged.plus(merged.additions(plan)) }
        end

        def read(path)
          header = nil
          results = {}
          recorded_keys = Set.new
          plan_records = []
          unidentified_results = 0

          File.foreach(path) do |line|
            line = line.strip
            next if line.empty?

            record = begin
              # Symbol keys throughout, so results read back are indistinguishable from the
              # ones EvalResult#to_h just produced and Run's summary can read both.
              JSON.parse(line, symbolize_names: true)
            rescue JSON::ParserError
              # A hard kill mid-write leaves a truncated final line: one lost result, not a
              # lost run.
              next
            end

            case record[:type]
            when "run"
              header = record
              plan_records << record[:plan] if record[:plan]
            when "plan"
              # Appended by a resume that found work the run had not planned - see #extend_plan!.
              plan_records << record[:plan] if record[:plan]
            when "result"
              result = normalize_result(record[:result])
              next if result.nil?

              (results[record[:eval_set]] ||= []) << result

              # A result from before evals carried an id has nothing to match a pending execution
              # against. Counted rather than keyed on nil, which would skip the whole run.
              if result[:eval_id].to_s.empty?
                unidentified_results += 1
                next
              end

              recorded_keys << RunLog.key(
                eval_id: result[:eval_id],
                case_id: result[:case_id],
                run_index: result[:run_index]
              )
            end
          end

          {
            header: header,
            results: results,
            recorded_keys: recorded_keys,
            plan_records: plan_records,
            unidentified_results: unidentified_results
          }
        end

        # JSON has no symbols, so an expectation's status comes back as a string where the run
        # summary compares it against :passed. Restored here rather than loosened there.
        def normalize_result(result)
          return unless result.is_a?(Hash)

          Array(result[:expectation_results]).each do |expectation|
            expectation[:status] = expectation[:status].to_sym if expectation[:status].is_a?(String)
          end

          result
        end

        # Compared after a JSON round trip: the live configuration holds symbols where the header
        # holds the strings they were written as, so :open_ai_gpt_4o must match "open_ai_gpt_4o".
        def configuration_differences(logged, current)
          logged = json_normalized(logged)
          current = json_normalized(current)

          (logged.keys | current.keys).flat_map do |key|
            next [] if PROVENANCE_KEYS.include?(key)
            next dataset_differences(logged[key], current[key]) if key == DATASETS_KEY
            next [] if logged[key] == current[key]

            ["  #{key}: log has #{logged[key].inspect}, this run has #{current[key].inspect}"]
          end
        end

        # Entry by entry, over the datasets both sides resolved. A resume narrowed to one eval set
        # file resolves only that file's datasets, and refusing over the ones this invocation never
        # looked at would make --resume unusable with a file argument. A dataset both sides did
        # resolve has to fingerprint the same: an edited case means different inputs under one id.
        def dataset_differences(logged, current)
          logged_by_key = dataset_index(logged)
          current_by_key = dataset_index(current)

          (logged_by_key.keys & current_by_key.keys).filter_map do |key|
            logged_entry = logged_by_key[key]
            current_entry = current_by_key[key]
            next if logged_entry["digest"] == current_entry["digest"]

            "  dataset #{key.compact.join(" in ")}: log has #{describe_dataset(logged_entry)}, " \
              "this run has #{describe_dataset(current_entry)}"
          end
        end

        def dataset_index(entries)
          entries = Array(entries).grep(Hash)

          entries.to_h { |entry| [[entry["name"], entry["eval_set"]], entry] }
        end

        def describe_dataset(entry)
          "#{entry["cases"]} cases (#{entry["digest"]})"
        end

        def json_normalized(configuration)
          JSON.parse(JSON.generate(configuration || {}))
        end
      end

      # The tuple that identifies one execution in the results JSON: which eval block, against
      # which case, on which repeat. The eval id already carries the eval set it belongs to, so
      # this key is unique across every set in the run.
      def self.key(eval_id:, case_id:, run_index:)
        [eval_id.to_s, case_id&.to_s, run_index]
      end

      def recorded?(eval_id:, case_id: nil, run_index: nil)
        @recorded_keys.include?(self.class.key(eval_id: eval_id, case_id: case_id, run_index: run_index))
      end

      # Adds executions the run did not originally plan and appends them to the log, so a later
      # resume owes them too. An eval block added to a file while the run was interrupted is the
      # case: Raif::Evals::Run warns about the code moving rather than refusing, so the new eval
      # runs, and the run is not complete until it has.
      #
      # Returns the keys that were new.
      def extend_plan!(other)
        added = plan.additions(other)
        return [] if added.empty?

        @mutex.synchronize do
          append({ type: "plan", plan: RunPlan.new(keys: added).to_h })
          @plan = plan.plus(added)
        end

        added
      end

      # The planned executions no result has been recorded for. Empty is what makes the run
      # finishable: see Raif::Evals::Run#export_results.
      def outstanding_keys
        @mutex.synchronize { plan.outstanding(@recorded_keys) }
      end

      def complete?
        outstanding_keys.empty?
      end

      # Appends one result and returns the hash that was written.
      def record(eval_set:, result:)
        payload = result.to_h

        @mutex.synchronize do
          append({ type: "result", eval_set: eval_set, result: payload })

          (@results[eval_set] ||= []) << payload
          @recorded_keys << self.class.key(
            eval_id: payload[:eval_id],
            case_id: payload[:case_id],
            run_index: payload[:run_index]
          )
        end

        payload
      end

      # A copy, so a caller counting results cannot be walking the array a concurrent #record is
      # pushing onto.
      def results_for(eval_set)
        @mutex.synchronize { (@results[eval_set] || []).dup }
      end

      # Derived from the log's own path so a resumed run completes the file its first attempt
      # was headed for, rather than opening a second one describing the same run.
      def results_path
        name = path.to_s
        name.end_with?(PARTIAL_SUFFIX) ? Pathname.new(name.delete_suffix(PARTIAL_SUFFIX) + ".json") : Pathname.new("#{name}.json")
      end

      def results_count
        @results.values.sum(&:count)
      end

      # Called once the final results file is written, and on a run that died before recording
      # anything, where a header-only log is nothing to resume.
      def discard!
        FileUtils.rm_f(path)
      end

      # For console output, where the absolute path is long enough to wrap in a terminal.
      def display_path
        path.relative_path_from(Rails.root).to_s
      rescue StandardError
        path.to_s
      end

    private

      # Opened and closed per record rather than held open for the run: the close hands the
      # line to the OS, so the log survives the process dying between two evals.
      def append(record)
        write(record, mode: "a")
      end

      def write_header(record)
        write(record, mode: "w")
      end

      def write(record, mode:)
        File.open(path, mode) do |file|
          file.puts(JSON.generate(record))
        end
      end
    end
  end
end
