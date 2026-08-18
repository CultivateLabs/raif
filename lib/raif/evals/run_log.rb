# frozen_string_literal: true

require "fileutils"
require "json"

module Raif
  module Evals
    # An append-only JSON Lines log of a run: a header line carrying the run's identity, then
    # one line per eval result as that result completes.
    #
    # A run's results file is only written once every eval set has finished, so without this a
    # run killed partway through would lose every result it had already paid for.
    # `raif evals --resume` reads the log back so that work is not bought twice.
    class RunLog
      PARTIAL_SUFFIX = ".partial.jsonl"

      # Raised when a resume would mix results that do not belong in one file together.
      class IncompatibleResumeError < StandardError; end

      attr_reader :path, :run_at, :configuration, :results

      def initialize(path:, run_at:, configuration:, results: {}, recorded_keys: nil)
        @path = Pathname.new(path.to_s)
        @run_at = run_at
        @configuration = configuration
        @results = results
        @recorded_keys = recorded_keys || Set.new
        # Concurrent evals record into one log. The append is one File.open per LLM-bound eval,
        # so serializing the whole of #record costs nothing next to what produced the result.
        @mutex = Mutex.new
      end

      class << self
        # Starts a fresh log and writes its header, so a run that dies before its first result
        # still leaves a file that identifies what was being run.
        def start(results_dir:, basename:, run_at:, configuration:)
          FileUtils.mkdir_p(results_dir)

          log = new(
            path: File.join(results_dir, "#{basename}#{PARTIAL_SUFFIX}"),
            run_at: run_at,
            configuration: configuration
          )

          # Truncating, unlike every write after it: a stale log left at the same path by an
          # abandoned run of the same second would otherwise gain a second header and read
          # back as one run.
          log.send(:write_header, { type: "run", run_at: run_at, configuration: configuration })
          log
        end

        # Reopens an interrupted run's log. The whole configuration has to match - see
        # Run#configuration_data.
        def resume(path:, configuration:)
          header, results, recorded_keys = read(path)

          if header.nil?
            raise IncompatibleResumeError, "#{path} has no run header line, so it is not a Raif eval run log."
          end

          differences = configuration_differences(header[:configuration], configuration)
          unless differences.empty?
            raise IncompatibleResumeError, <<~MSG.strip
              Refusing to resume #{path}: this run was started with different settings.

              #{differences.join("\n")}

              Re-run with the settings the log was started with, or drop --resume to start a new run.
            MSG
          end

          new(
            path: path,
            run_at: header[:run_at],
            configuration: configuration,
            results: results,
            recorded_keys: recorded_keys
          )
        end

        # The configuration a log was started with, read without opening it for writing. A
        # resumed run needs one value out of it - the seed - before it can state its own
        # configuration, since a sampled run has to draw the same cases its first attempt did.
        # Returns nil for anything that is not a readable log; #resume is what reports on that.
        def logged_configuration(path)
          header, = read(path)
          header && header[:configuration]
        rescue SystemCallError
          nil
        end

      private

        def read(path)
          header = nil
          results = {}
          recorded_keys = Set.new

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
            when "result"
              result = normalize_result(record[:result])
              next if result.nil?

              (results[record[:eval_set]] ||= []) << result
              recorded_keys << RunLog.key(
                eval_set: record[:eval_set],
                eval_index: result[:eval_index],
                case_id: result[:case_id],
                run_index: result[:run_index]
              )
            end
          end

          [header, results, recorded_keys]
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

        # Compared after a JSON round trip: the live configuration holds symbols where the
        # header holds the strings they were written as, so :open_ai_gpt_4o has to match
        # "open_ai_gpt_4o".
        def configuration_differences(logged, current)
          logged = json_normalized(logged)
          current = json_normalized(current)

          (logged.keys | current.keys).filter_map do |key|
            next if logged[key] == current[key]

            "  #{key}: log has #{logged[key].inspect}, this run has #{current[key].inspect}"
          end
        end

        def json_normalized(configuration)
          JSON.parse(JSON.generate(configuration || {}))
        end
      end

      # The tuple that identifies one execution in the results JSON: which eval block, against
      # which case, on which repeat.
      def self.key(eval_set:, eval_index:, case_id:, run_index:)
        [eval_set.to_s, eval_index, case_id&.to_s, run_index]
      end

      def recorded?(eval_set:, eval_index:, case_id: nil, run_index: nil)
        @recorded_keys.include?(
          self.class.key(eval_set: eval_set, eval_index: eval_index, case_id: case_id, run_index: run_index)
        )
      end

      # Appends one result and returns the hash that was written.
      def record(eval_set:, result:)
        payload = result.to_h

        @mutex.synchronize do
          append({ type: "result", eval_set: eval_set, result: payload })

          (@results[eval_set] ||= []) << payload
          @recorded_keys << self.class.key(
            eval_set: eval_set,
            eval_index: payload[:eval_index],
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
