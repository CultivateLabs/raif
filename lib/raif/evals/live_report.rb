# frozen_string_literal: true

require "erb"
require "fileutils"
require "rbconfig"

module Raif
  module Evals
    # A self-contained HTML page that describes a run while it continues. It is rewritten as each
    # execution starts and finishes, reloads itself in the browser, and is replaced by the full
    # Raif::Evals::RunReport at the same path when the run completes.
    #
    # Ruby writes the page, rather than JavaScript on the page reading the run log, because a page
    # opened from disk cannot fetch a neighbouring file. The run log stays the source of truth: every
    # rewrite is rendered from a snapshot of it, and this class adds only what the log cannot know -
    # which executions are in flight and how long the finished ones took.
    #
    # Each rewrite goes to a temporary file that is then renamed over the page, so a reload sees the
    # previous page or the next one and never half of either.
    class LiveReport
      TEMPLATE_PATH = File.expand_path("live_report.html.erb", __dir__)

      REFRESH_SECONDS = 30

      # Below this many timed executions an average says more about one slow case than about the run.
      MIN_TIMED_FOR_ESTIMATE = 3

      attr_reader :path

      def initialize(path:, run_log:, configuration:, concurrency:, output:)
        @path = Pathname.new(path.to_s)
        @run_log = run_log
        @configuration = configuration
        @concurrency = concurrency
        @output = output
        @running = {}
        @finish_order = []
        @durations = []
        @stopped = nil
        @disabled = false
        # Workers start and finish executions concurrently. One lock around render-and-write keeps
        # two rewrites from racing on the temporary file, and keeps the running list consistent.
        @mutex = Mutex.new
      end

      # @param executions [Integer] how many executions this invocation will run. The estimate of the
      #   time left is over these, since a resume narrowed to one file will not run the rest of the plan.
      def start!(executions:)
        synchronized_publish do
          @executions = executions
        end
      end

      def execution_started(execution, eval_set_name:)
        synchronized_publish do
          @running[key_for(execution)] = {
            eval_set: eval_set_name,
            description: execution.eval_definition.description,
            case_id: execution.eval_case&.id,
            run_index: execution.run_index,
            started_at: Time.current,
            started: monotonic_now
          }
        end
      end

      # Called whether or not the execution recorded a result, so a failure cannot leave it listed
      # as running.
      def execution_finished(execution)
        synchronized_publish do
          key = key_for(execution)
          entry = @running.delete(key)
          @durations << (monotonic_now - entry[:started]) if entry
          @finish_order << key
        end
      end

      # The last rewrite of a run that ended without completing its plan. It carries no reload tag,
      # so the page stops refreshing a run that is no longer there.
      def stop!(reason:, resume_command: nil)
        synchronized_publish do
          @running.clear
          @stopped = { reason: reason, resume_command: resume_command }
        end
      end

      # The block renders the full run report, which takes over the page's path. Rendered inside
      # the guard in #publish, since the results file is already written and a report that fails
      # to render is no reason to fail the run. Returns whether the report was written.
      def complete!(&render_report)
        @mutex.synchronize { publish(&render_report) }
      end

      # For a run that stopped before it recorded anything, whose run log is deleted with it.
      def discard!
        @mutex.synchronize do
          @disabled = true
          FileUtils.rm_f(path)
        end
      end

      # Hands the page to the platform's opener and does not wait for it. Skipped when the page
      # was never written, and a failed launch costs one warning, never the run.
      def open_in_browser
        return if @disabled || !path.exist?

        pid = Process.spawn(*browser_command, path.to_s, out: File::NULL, err: File::NULL)
        Process.detach(pid)
      rescue SystemCallError => e
        @output.puts Raif::Utils::Colors.yellow("\nCould not open the live report in a browser: #{e.message}")
      end

      def display_path
        path.relative_path_from(Rails.root).to_s
      rescue StandardError
        path.to_s
      end

      # Everything below is read by the template, against the snapshot taken for one rewrite.

      def refresh_seconds
        REFRESH_SECONDS
      end

      def running?
        @stopped.nil?
      end

      def stopped
        @stopped
      end

      def rendered_at
        @rendered_at.strftime("%Y-%m-%d %H:%M:%S")
      end

      def run_at
        @run_log.run_at.to_s.sub("T", " ")[0, 16]
      end

      def model
        @configuration[:default_llm_model_key]
      end

      def judge
        @configuration[:judge_model_key] || @configuration[:evals_default_llm_judge_model_key]
      end

      def concurrency
        @concurrency
      end

      def describe_code
        code = @configuration[:code]
        return "unknown" if code.nil?

        "#{code[:git_sha].to_s[0, 12]}#{" (dirty)" if code[:dirty]}"
      end

      def expected
        @snapshot[:plan].size
      end

      def completed
        results.count
      end

      def outstanding
        @snapshot[:outstanding].count
      end

      def percent_complete
        return 0 if expected.zero?

        ((completed.to_f / expected) * 100).floor
      end

      def counts
        @counts ||= tally(results.map { |_eval_set, result| result })
      end

      def total_cost
        results.sum { |_eval_set, result| result.dig(:usage, :total_cost).to_f }
      end

      def judge_cost
        results.sum { |_eval_set, result| result.dig(:judge_usage, :total_cost).to_f }
      end

      # Across every invocation of a resumed run, so the page agrees with the report that replaces it.
      def elapsed
        format_duration(@run_log.elapsed_seconds)
      end

      # Of the executions that measured something: errored ones leave the denominator, as they do in
      # every pass rate Raif reports.
      def percent_of_measured(count)
        measured = completed - counts[:errored]
        return if measured.zero?

        (count * 100.0 / measured).round
      end

      # Average duration of this invocation's finished executions, times what it has left, spread
      # over the workers. Results a resume carried forward have no timing, so they do not count.
      def time_left
        return "-" if @durations.size < MIN_TIMED_FOR_ESTIMATE

        remaining = [@executions.to_i - @finish_order.size, 0].max
        return "-" if remaining.zero?

        average = @durations.sum / @durations.size
        "~#{format_duration(average * remaining / [@concurrency, remaining].min)}"
      end

      # One row per eval set, in plan order. Expected comes from the plan, so a set with nothing
      # finished yet still shows what it owes.
      def eval_set_rows
        expected_by_set = @snapshot[:plan].keys.group_by { |eval_id, _case_id, _run_index| eval_id.split("#").first }
        names = expected_by_set.keys | @snapshot[:results].keys.map(&:to_s)

        names.map do |name|
          set_results = @snapshot[:results][name] || @snapshot[:results][name.to_sym] || []
          { name: name, expected: expected_by_set.fetch(name, []).size, completed: set_results.size }.merge(tally(set_results))
        end
      end

      def running_rows
        @running.values.sort_by { |entry| entry[:started] }
      end

      def running_for(entry)
        format_duration(monotonic_now - entry[:started])
      end

      # Every expectation that did not pass, in the order the results were recorded.
      def failures
        results.flat_map do |eval_set_name, result|
          Array(result[:expectation_results]).each_with_index.filter_map do |expectation, index|
            next if expectation[:status].to_s == "passed"

            {
              eval_set: eval_set_name,
              description: result[:description],
              case_id: result[:case_id],
              run_index: result[:run_index],
              expectation: expectation,
              key: "failure:#{result_key(result).join("|")}|#{index}"
            }
          end
        end
      end

      # Newest first. Results this invocation finished are ordered by when they finished; results a
      # resume carried forward have no finish time here, so they follow in the order the log holds.
      def completed_rows
        order = @finish_order.each_with_index.to_h

        results.each_with_index.sort_by do |(_eval_set, result), index|
          position = order[result_key(result)]
          position ? [0, -position] : [1, index]
        end.map(&:first)
      end

      def result_status(result)
        return ["ERROR", "warn"] if result[:errored]

        result[:passed] ? ["PASS", "good"] : ["FAIL", "bad"]
      end

      def status_class(status)
        case status.to_s
        when "passed" then "good"
        when "error" then "warn"
        else "bad"
        end
      end

      def format_cost(cost)
        value = cost.to_f
        value >= 1 ? format("$%.2f", value) : format("$%.4f", value)
      end

      def stylesheet
        File.read(RunReport::STYLESHEET_PATH)
      end

      # Model output reaches this page as expectation metadata and judge reasoning.
      def h(value)
        ERB::Util.html_escape(value.to_s)
      end

      def pretty(value)
        JSON.pretty_generate(value)
      rescue JSON::GeneratorError, TypeError
        value.inspect
      end

    private

      # The block updates state; the page is then rendered from it and written, all under the lock.
      def synchronized_publish
        @mutex.synchronize do
          yield
          publish { render }
        end
      end

      # A page that fails to render or write must not cost the run, which is spending money on every
      # execution. The first failure is reported once and the page is left as it was.
      def publish
        return false if @disabled

        write(yield)
        true
      rescue StandardError => e
        @disabled = true
        @output.puts Raif::Utils::Colors.yellow("\nLive report disabled for the rest of this run: #{e.class}: #{e.message}")
        false
      end

      def write(html)
        FileUtils.mkdir_p(path.dirname)
        temporary = path.dirname.join(".#{path.basename}.#{Process.pid}.tmp")
        File.write(temporary, html)
        File.rename(temporary, path)
      ensure
        FileUtils.rm_f(temporary) if temporary && File.exist?(temporary)
      end

      def render
        @snapshot = @run_log.snapshot
        @rendered_at = Time.current
        @results = nil
        @counts = nil

        template.result(binding)
      end

      def template
        @template ||= ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-")
      end

      # [eval set name, result] pairs, in the order the log holds them.
      def results
        @results ||= @snapshot[:results].flat_map do |eval_set_name, set_results|
          set_results.map { |result| [eval_set_name.to_s, result] }
        end
      end

      def tally(set_results)
        errored = set_results.count { |result| result[:errored] }
        passed = set_results.count { |result| result[:passed] }

        { passed: passed, errored: errored, failed: set_results.size - passed - errored }
      end

      def key_for(execution)
        RunPlan.normalize([execution.eval_id, execution.eval_case&.id, execution.run_index])
      end

      def result_key(result)
        RunPlan.normalize([result[:eval_id], result[:case_id], result[:run_index]])
      end

      def format_duration(seconds)
        RunReport.format_duration(seconds)
      end

      def browser_command
        case RbConfig::CONFIG["host_os"]
        when /darwin/ then ["open"]
        when /mswin|mingw|cygwin/ then ["cmd", "/c", "start", ""]
        else ["xdg-open"]
        end
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
