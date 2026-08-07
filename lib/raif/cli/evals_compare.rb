# frozen_string_literal: true

require "optparse"
require "json"
require_relative "base"

module Raif
  module CLI
    class EvalsCompare < Base
      FORMATS = ["text", "json", "html"].freeze

      # Rails is deliberately not loaded: this reads two JSON files and does arithmetic, and
      # booting an app to do it would make the one part of the eval tooling that needs no
      # database or API key the slowest to run.
      def run
        format = "text"
        threshold = nil
        allow_judge_mismatch = false

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: raif evals:compare BASELINE_RESULTS.json CANDIDATE_RESULTS.json [options]"

          opts.on("--fail-on-regression N", Float,
            "Exit non-zero when a pass rate or gated score gets more than N worse than baseline, as a " \
            "fraction of it (0.25 = 25% worse)") do |n|
            threshold = n
          end

          opts.on("--format FORMAT", FORMATS, "Output format: #{FORMATS.join(", ")} (default: text)") do |value|
            format = value
          end

          opts.on("--allow-judge-mismatch", "Compare runs that used different judge models anyway") do
            allow_judge_mismatch = true
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end

        parse_options!(parser)

        baseline_path, candidate_path = args
        if baseline_path.nil? || candidate_path.nil?
          puts parser
          exit 1
        end

        require_relative "../evals/statistics"
        require_relative "../evals/comparison"
        require_relative "../evals/comparison_report"
        require_relative "../utils/colors"

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
          MSG
          exit 2
        end

        report = Raif::Evals::ComparisonReport.new(comparison, threshold: threshold, color: format == "text")

        if format == "html"
          output_path = html_output_path(candidate_path, baseline_path)
          File.write(output_path, report.render("html"))
          puts "Comparison report written to: #{output_path}"
        else
          puts report.render(format)
        end

        exit 1 if comparison.regressed?(threshold)
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

        # Shape-checked rather than trusted. Every key this command reads is looked up with a nil
        # fallback, so an unrecognized JSON object compares cleanly against another one and
        # reports no regressions - and this command's whole job is to exit non-zero when there is
        # one. `--format json` writes its own report into the same results directory, with
        # baseline/candidate keys instead of results, which makes feeding one back in an easy
        # mistake to make and an expensive one to not notice.
        unless payload.is_a?(Hash) && payload["results"].is_a?(Hash)
          puts Raif::Utils::Colors.red(<<~MSG)
            Error: #{path} is not a Raif eval results file (no top-level "results" object).
            Pass the JSON files written to raif_evals/results by `raif evals`, baseline first.
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
