# frozen_string_literal: true

require "erb"
require "json"

# evals:compare deliberately does not boot Rails, so this file is loaded on its own rather
# than through raif/evals.rb and cannot rely on that file's require order.
require_relative "console_line"

module Raif
  module Evals
    # Renders a Comparison as console text, JSON, or a self-contained HTML file.
    class ComparisonReport
      TEMPLATE_PATH = File.expand_path("comparison_report.html.erb", __dir__)

      attr_reader :comparison, :threshold, :alpha, :max_error_rate

      def initialize(comparison, threshold: nil, color: true, alpha: Comparison::FAMILY_WISE_ALPHA,
        max_error_rate: Comparison::MAX_GATE_ERROR_RATE)
        @comparison = comparison
        @threshold = threshold
        @color = color
        @alpha = alpha
        @max_error_rate = max_error_rate
      end

      def render(format)
        case format.to_s
        when "json" then JSON.pretty_generate(comparison.to_h)
        when "html" then html
        else text
        end
      end

      def html
        ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-").result(binding)
      end

      def text
        lines = ["", "Comparing eval runs", ""]
        lines.concat(header_lines)
        lines.concat(section("NEW FAILURES", comparison.new_failures) { |row| rate_lines(row, :red) })
        lines.concat(section("FIXED", comparison.fixed) { |row| rate_lines(row, :green) })
        lines.concat(section("SCORE MOVES", comparison.score_moves) { |row| score_lines(row) })
        lines.concat(section("ERROR RATES", comparison.error_moves) { |row| error_lines(row) })
        lines.concat(section("NOT COMPARABLE", comparison.not_comparable) { |row| not_comparable_lines(row) })
        lines.concat(section("REGRESSION GATE", comparison.candidate_regressions(threshold)) { |row| regression_lines(row) })
        lines.concat(summary_lines)
        lines.join("\n")
      end

      # Public so the HTML template shares it with #text and the two cannot drift.
      def score_headline(row)
        parts = [score_relative(row), score_spread(row)].compact
        parts << "not gated" unless row[:gated]

        "#{row[:name]}  #{row[:baseline_mean]} -> #{row[:candidate_mean]}  #{format_delta(row[:delta])}  (#{parts.join(", ")})"
      end

      # Printed alongside the absolute delta because --fail-on-regression is relative to the
      # baseline: whether -1.0 clears a 0.25 threshold depends on what it is -1.0 of. nil when
      # the baseline mean is zero and there is no fraction to take.
      def score_relative(row)
        baseline = row[:baseline_mean].to_f.abs
        return if baseline.zero?

        format("%+.1f%%", (row[:delta].to_f / baseline) * 100)
      end

      # A single observation has no standard deviation, so one side can be absent while the other is
      # real. The sd fragment is dropped only when neither side has one. spread_n is named apart
      # from n because they differ on a dataset score: n counts every observation, sd is over the
      # per-case means, and printing only n would overstate what the spread was measured on.
      def score_spread(row)
        baseline = row[:baseline_stddev]
        candidate = row[:candidate_stddev]
        parts = ["n=#{row[:candidate_n]}"]
        parts << "over #{row[:spread_n]} cases" if row[:spread_n] && row[:spread_n] != row[:candidate_n]
        parts << "sd #{baseline || "-"} -> #{candidate || "-"}" unless baseline.nil? && candidate.nil?

        parts.join(", ")
      end

      # How sure the gate is that a row is not noise, in the terms the reader has to act on: what
      # was paired, how it split, and the p-value that came out. Nothing to say for a row that is
      # not a regression candidate, which is most of them.
      def evidence_summary(row)
        case row[:evidence]
        when :paired_cases then "#{row[:worsened]}/#{row[:pairs]} cases worse, #{format_p(row[:p_value])}"
        when :repeats then "repeats only, #{format_p(row[:p_value])}"
        else "no matched cases to test - add dataset cases, or --significance 1 to gate on size alone"
        end
      end

      # Loud and not a refusal - see Comparison#dataset_differences. Public so evals:compare can
      # print it when --format html sent the report to a file instead of the screen.
      def dataset_warning
        return if comparison.dataset_differences.empty?

        lines = ["Warning: these two runs did not measure the same datasets:"]

        comparison.dataset_differences.each do |row|
          lines << "  #{row[:name]} (#{row[:eval_set]}): #{row[:baseline]} -> #{row[:candidate]}"
        end

        lines << "  Cases are joined by id, so a difference the dataset caused reads as a difference the model caused."
        lines << "  Re-run the baseline against the current dataset to compare the two models alone."
        lines.join("\n")
      end

      # "unknown" rather than blank for a run recorded before the git sha was: what code produced it
      # was not recorded, which is different from having been produced by no code.
      def describe_code(code)
        return "unknown" if code.nil?

        "#{code["git_sha"].to_s[0, 12]}#{" (dirty)" if code["dirty"]}"
      end

      # "-" rather than $0.00 for a run recorded before judge spend was tagged: it is not known to
      # be zero, and a zero would read as "this run used no judge".
      def format_cost(cost)
        return "-" if cost.nil?

        "$#{format("%.2f", cost.to_f)}"
      end

      # Only when a judge actually spent something on one side or the other: a run that used no
      # judge would otherwise gain two rows saying so twice.
      def cost_split?
        [comparison.to_h[:baseline], comparison.to_h[:candidate]].any? { |side| side[:judge_cost].to_f.positive? }
      end

      def gated_rows
        @gated_rows ||= comparison.significant_regressions(threshold, alpha: alpha)
      end

      # A p-value rounded to 6 places can land on 0.0, which reads as a bug rather than as
      # "smaller than this report shows".
      def format_p(p_value)
        return "p n/a" if p_value.nil?
        return "p<0.000001" if p_value.zero?

        "p=#{p_value}"
      end

      def format_delta(delta)
        delta.to_f.positive? ? "+#{delta}" : delta.to_s
      end

      def format_rate(rate)
        format("%.2f", rate.to_f)
      end

      # The number the SUMMARY prints beside "evals errored". Not a pass rate's denominator: this
      # one is every run, since the question is how much of the run was lost.
      def error_fraction(side)
        "#{side[:errored_evals]}/#{side[:total_evals]} (#{format("%.1f%%", side[:error_rate].to_f * 100)})"
      end

      # The threshold is restated as a percentage: a bare "0.25" next to a list of absolute deltas
      # invites reading it as those deltas' units rather than as a fraction of baseline.
      #
      # Five outcomes, not two. A row can clear the size bar and still not be distinguishable from
      # run-to-run variation, and saying so keeps the reader from concluding either that nothing
      # moved or that something definitely did. The error ceiling is checked ahead of all of it,
      # since a run that lost too much to errors cannot support any of those readings.
      def verdict
        return "no regression threshold set (--fail-on-regression)" if threshold.nil?

        if comparison.error_rate_unreliable?(max_error_rate: max_error_rate)
          return "gate declined: #{format("%.1f%%", [comparison.baseline_error_rate, comparison.candidate_error_rate].max * 100)} " \
            "of runs errored, above the #{format("%g", max_error_rate.to_f * 100)}% ceiling (exit 2)"
        end

        gate = "--fail-on-regression #{threshold} (#{format("%g", threshold.to_f * 100)}% worse than baseline)"
        candidates = comparison.candidate_regressions(threshold)
        significant = comparison.significant_regressions(threshold, alpha: alpha)

        return "no regression beyond #{gate}" if candidates.empty?

        if significant.any?
          return "#{significant.count} regression#{"s" if significant.count != 1} beyond #{gate}, " \
            "#{evidence_note} (exit 1)"
        end

        if comparison.insufficient_evidence?(threshold, alpha: alpha)
          return "#{candidates.count} regression#{"s" if candidates.count != 1} beyond #{gate}, none of them testable - " \
            "#{unverifiable_advice} (exit 2)"
        end

        "#{candidates.count} regression#{"s" if candidates.count != 1} beyond #{gate}, none distinguishable from " \
          "run-to-run variation #{evidence_note}"
      end

      def evidence_note
        return "evidence not required (--significance #{alpha})" if alpha.nil? || alpha.to_f >= 1.0

        count = comparison.candidate_regressions(threshold).count
        "at a family-wise #{alpha} over #{count} candidate row#{"s" if count != 1}"
      end

      def unverifiable_advice
        "a dataset gives the gate matched cases to test; --repeat sharpens each case rather than " \
          "creating pairs. Pass --significance 1 to gate on effect size alone."
      end

      def h(value)
        ERB::Util.html_escape(value.to_s)
      end

      def run_at(value)
        value.to_s.sub("T", " ")[0, 16]
      end

    private

      def header_lines
        baseline = comparison.to_h[:baseline]
        candidate = comparison.to_h[:candidate]
        judge = if comparison.judge_mismatch?
          colorize("#{baseline[:judge]} -> #{candidate[:judge]} (MISMATCHED)", :yellow)
        else
          "#{candidate[:judge]} (both runs)"
        end

        lines = [
          "  baseline   #{side_line(baseline)}",
          "  candidate  #{side_line(candidate)}",
          "  judge      #{judge}"
        ]

        if [baseline[:code], candidate[:code]].any?
          lines << "  code       #{describe_code(baseline[:code])} -> #{describe_code(candidate[:code])}"
        end

        if dataset_warning
          lines << ""
          lines << colorize(dataset_warning, :yellow)
        end

        lines << ""
        lines
      end

      def side_line(side)
        [
          side[:model],
          run_at(side[:run_at]),
          "#{side[:evals]} evals x #{side[:repeats]} repeats",
          ("#{side[:cases]} cases" if side[:cases].to_i.positive?),
          "$#{format("%.2f", side[:total_cost].to_f)}",
          side[:label]
        ].compact.join("   ")
      end

      def section(title, rows)
        return [] if rows.empty?

        lines = ["#{title} (#{rows.count})"]
        rows.each { |row| lines.concat(yield(row)) }
        lines << ""
        lines
      end

      def rate_lines(row, color)
        lines = ["  #{row[:eval_set]}  #{row[:description]}"]
        transition = "#{format_rate(row[:baseline_rate])} -> #{format_rate(row[:candidate_rate])}"
        lines << "    #{colorize("#{(row[:case_id] || "-").ljust(20)} #{transition}", color)}"

        row[:expectations].each do |move|
          description = ConsoleLine.truncate_description(move[:description])
          lines << "      #{format_rate(move[:baseline_rate])} -> #{format_rate(move[:candidate_rate])}  #{description}"
        end

        lines
      end

      def score_lines(row)
        color = row[:regression] > 0 ? :red : :green
        lines = ["  #{colorize(score_headline(row), color)}"]

        row[:per_case].each do |per_case|
          lines << "    #{per_case[:case_id].ljust(20)} #{per_case[:baseline_mean]} -> #{per_case[:candidate_mean]}  " \
            "#{format_delta(per_case[:delta])}"
        end

        lines
      end

      # The gate's own rows, so a reader can see why it decided what it decided. One row per eval
      # rather than per case: per-case detail is in NEW FAILURES, which reports where this acts.
      def regression_lines(row)
        size = row[:magnitude].nil? ? "unbounded (baseline was 0)" : "#{format("%g", row[:magnitude] * 100)}% worse"
        color = gated_rows.include?(row) ? :red : :yellow

        [
          "  #{colorize("#{row[:label]} (#{row[:kind]})", color)}",
          "    #{size}, #{row[:absolute]} absolute   #{evidence_summary(row)}"
        ]
      end

      # Yellow either way: an error rate that moved in either direction is a fact about the
      # infrastructure, not a verdict on the model, and neither red nor green would say that.
      def error_lines(row)
        transition = "#{row[:baseline_errored]}/#{row[:baseline_runs]} -> #{row[:candidate_errored]}/#{row[:candidate_runs]} runs errored"

        [
          "  #{row[:eval_set]}  #{row[:description]}",
          "    #{colorize("#{format_rate(row[:baseline_rate])} -> #{format_rate(row[:candidate_rate])}  #{transition}", :yellow)}"
        ]
      end

      def not_comparable_lines(row)
        label = [row[:case_id] || "-", row[:expectation]].compact.join(" / ")
        ["  #{row[:eval_set]}  #{row[:description]}", "    #{label.ljust(20)} #{row[:reason] || row[:present_in]}"]
      end

      def summary_lines
        baseline = comparison.to_h[:baseline]
        candidate = comparison.to_h[:candidate]

        lines = ["SUMMARY"]
        lines << "  evals passed          #{baseline[:passed_evals]}/#{baseline[:total_evals]} -> " \
          "#{candidate[:passed_evals]}/#{candidate[:total_evals]}"
        lines << "  expectations          #{baseline[:passed_expectations]}/#{baseline[:total_expectations]} -> " \
          "#{candidate[:passed_expectations]}/#{candidate[:total_expectations]}"

        # Only when a side lost something: on a clean run this is two zeroes and a distraction
        # from the numbers the reader came for.
        if [baseline[:errored_evals], candidate[:errored_evals]].any? { |count| count.to_i.positive? }
          lines << "  #{colorize("evals errored", :yellow)}         #{error_fraction(baseline)} -> #{error_fraction(candidate)}"
        end

        comparison.score_moves.each do |row|
          lines << "  mean #{row[:name].ljust(16)} #{row[:baseline_mean]} -> #{row[:candidate_mean]}"
        end

        lines << "  total cost            $#{format("%.2f", baseline[:total_cost].to_f)} -> " \
          "$#{format("%.2f", candidate[:total_cost].to_f)}"

        # Indented under the total, which they split rather than add to. The subject line answers
        # "is this model more expensive": the judge is the same on both sides by design.
        if cost_split?
          lines << "    model under test    #{format_cost(baseline[:subject_cost])} -> #{format_cost(candidate[:subject_cost])}"
          lines << "    judge               #{format_cost(baseline[:judge_cost])} -> #{format_cost(candidate[:judge_cost])}"
        end
        lines << "  #{verdict}"
        lines << ""
        lines
      end

      def colorize(text, color)
        @color ? Raif::Utils::Colors.public_send(color, text) : text
      end
    end
  end
end
