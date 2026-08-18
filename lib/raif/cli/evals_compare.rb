# frozen_string_literal: true

require "optparse"
require "json"
require_relative "base"

module Raif
  module CLI
    class EvalsCompare < Base
      FORMATS = ["text", "json", "html"].freeze

      # Rails is deliberately not loaded: this reads two JSON files and does arithmetic, so
      # booting an app would make the one part of the eval tooling that needs no database or
      # API key the slowest to run. These four are plain Ruby with no Rails dependency, and are
      # required up front rather than after parsing so the --significance help text can name the
      # real default instead of a copy of it that could drift.
      def run
        require_relative "../evals/statistics"
        require_relative "../evals/comparison"
        require_relative "../evals/comparison_report"
        require_relative "../utils/colors"

        format = "text"
        threshold = nil
        allow_judge_mismatch = false
        alpha = nil
        max_error_rate = Raif::Evals::Comparison::MAX_GATE_ERROR_RATE

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: raif evals:compare BASELINE_RESULTS.json CANDIDATE_RESULTS.json [options]"

          opts.on("--fail-on-regression N", Float,
            "Exit non-zero when a pass rate or gated score gets more than N worse than baseline, as a " \
            "fraction of it (0.25 = 25% worse)") do |n|
            threshold = n
          end

          opts.on("--significance ALPHA", Float,
            "Family-wise significance level a regression must clear as well as the threshold " \
            "(default: #{Raif::Evals::Comparison::FAMILY_WISE_ALPHA}). 1 waives it and gates on effect size alone.") do |value|
            alpha = value
          end

          opts.on("--format FORMAT", FORMATS, "Output format: #{FORMATS.join(", ")} (default: text)") do |value|
            format = value
          end

          opts.on("--allow-judge-mismatch", "Compare runs that used different judge models anyway") do
            allow_judge_mismatch = true
          end

          opts.on("--max-error-rate N", Float,
            "Fraction of runs either side may lose to errors before --fail-on-regression declines to " \
            "decide (default: #{Raif::Evals::Comparison::MAX_GATE_ERROR_RATE}). 1 gates regardless.") do |value|
            max_error_rate = value
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end

        parse_options!(parser)

        # A level outside (0, 1] is a typo with a silent failure mode at each end: 0 can never be
        # cleared, so the gate would never fire, and a negative one reads as "definitely gate" while
        # doing the same thing.
        if alpha && (alpha <= 0 || alpha > 1)
          puts "Error: --significance must be greater than 0 and at most 1 (got #{alpha})"
          exit 1
        end

        if max_error_rate.negative? || max_error_rate > 1
          puts "Error: --max-error-rate must be between 0 and 1 (got #{max_error_rate})"
          exit 1
        end

        baseline_path, candidate_path = args
        if baseline_path.nil? || candidate_path.nil?
          puts parser
          exit 1
        end

        comparison = Raif::Evals::Comparison.new(
          baseline: load_payload(baseline_path),
          candidate: load_payload(candidate_path),
          baseline_label: File.basename(baseline_path),
          candidate_label: File.basename(candidate_path)
        )

        if comparison.judge_mismatch? && !allow_judge_mismatch
          puts Raif::Utils::Colors.red(<<~MSG)
            Refusing to compare runs judged by different models:
              baseline:  #{comparison.baseline_judge.inspect}
              candidate: #{comparison.candidate_judge.inspect}

            Scores from two judges measure two different things. Re-run one arm with the other's
            judge, or pass --allow-judge-mismatch if you know the difference does not matter here.

            A run with no Raif.config.evals_default_llm_judge_model_key set is graded by the model
            under test, so comparing two models changes the judge unless one is configured.
          MSG
          exit 2
        end

        alpha ||= Raif::Evals::Comparison::FAMILY_WISE_ALPHA
        report = Raif::Evals::ComparisonReport.new(
          comparison,
          threshold: threshold,
          color: format == "text",
          alpha: alpha,
          max_error_rate: max_error_rate
        )

        if format == "html"
          output_path = html_output_path(candidate_path, baseline_path)
          File.write(output_path, report.render("html"))

          # The report went to a file rather than the screen, and a dataset that changed under the
          # comparison is the one thing in it a reader has to see before reading the rest. The other
          # two formats carry it themselves - text in its header, json in dataset_differences.
          dataset_warning = report.dataset_warning
          puts Raif::Utils::Colors.yellow(dataset_warning) if dataset_warning

          puts "Comparison report written to: #{output_path}"
        else
          puts report.render(format)
        end

        # Ahead of the gate rather than after it: a run that lost this much to errors cannot
        # support a verdict either way, for the reason Comparison#error_rate_unreliable? gives
        # and the message below repeats. 2 rather than 1, matching the refusals around it.
        if threshold && comparison.error_rate_unreliable?(max_error_rate: max_error_rate)
          puts Raif::Utils::Colors.red(<<~MSG)
            Refusing to pass or fail: too many runs errored to gate on this comparison.
              baseline:  #{format("%.1f%%", comparison.baseline_error_rate * 100)} of runs errored
              candidate: #{format("%.1f%%", comparison.candidate_error_rate * 100)} of runs errored
              ceiling:   #{format("%g%%", max_error_rate * 100)} (--max-error-rate)

            Errored runs are excluded from the pass rates rather than counted as failures, so the
            rates above are sound - but the runs that survived may not be a fair sample of the ones
            that did not, and a gate cannot tell the difference.

            Re-run the failing arm, or pass --max-error-rate 1 to gate on the surviving runs anyway.
          MSG
          exit 2
        end

        exit 1 if comparison.regressed?(threshold, alpha: alpha)

        # Something moved past the threshold and none of it could be tested, so the gate has no
        # answer to give. Exiting 0 here would report a run that may well have regressed as clean,
        # which is the failure mode a gate exists to prevent; 2 matches the judge mismatch above -
        # refusing to decide, rather than deciding against.
        if comparison.insufficient_evidence?(threshold, alpha: alpha)
          puts Raif::Utils::Colors.red(<<~MSG)
            Refusing to pass or fail: #{comparison.unverifiable_regressions(threshold).count} regression(s) cleared the
            --fail-on-regression threshold, but none of them can be told apart from run-to-run variation.

            The gate tests matched dataset cases. An eval with no dataset has none, and --repeat
            sharpens each case's estimate rather than creating pairs to compare.

            Give the evals a dataset, or pass --significance 1 to gate on effect size alone.
          MSG
          exit 2
        end
      end

    private

      def load_payload(path)
        unless File.exist?(path)
          puts Raif::Utils::Colors.red("Error: File not found: #{path}")
          exit 1
        end

        payload = begin
          JSON.parse(File.read(path))
        rescue JSON::ParserError => e
          puts Raif::Utils::Colors.red("Error: #{path} is not valid JSON: #{e.message}")
          exit 1
        end

        # Every key this command reads is looked up with a nil fallback, so without a shape
        # check two unrecognized JSON objects would compare cleanly and report no regressions -
        # from a command whose whole job is to exit non-zero when there is one. `--format json`
        # writes its own report into the same results directory, so feeding one back in is an
        # easy mistake to make.
        unless payload.is_a?(Hash) && payload["results"].is_a?(Hash)
          puts Raif::Utils::Colors.red(<<~MSG)
            Error: #{path} is not a Raif eval results file (no top-level "results" object).
            Pass the JSON files written to raif_evals/results by `raif evals`, baseline first.
          MSG
          exit 1
        end

        # Results are joined on eval_id. Without one, every result keys on nil, collapses into a
        # single unit per case, and diffs against the wrong eval - what the id exists to prevent.
        results = payload["results"].values.flatten.compact
        if results.any? { |result| !result.is_a?(Hash) || result["eval_id"].to_s.empty? }
          puts Raif::Utils::Colors.red(<<~MSG)
            Error: #{path} was written before evals had ids, so its results cannot be matched to another run's.
            Re-run the evals to produce a comparable results file.
          MSG
          exit 1
        end

        payload
      end

      # Next to the candidate results file, since that is the run being judged.
      def html_output_path(candidate_path, baseline_path)
        File.join(
          File.dirname(candidate_path),
          "eval_comparison_#{File.basename(baseline_path, ".json")}_vs_#{File.basename(candidate_path, ".json")}.html"
        )
      end
    end
  end
end
