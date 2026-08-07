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

      attr_reader :comparison, :threshold

      def initialize(comparison, threshold: nil, color: true)
        @comparison = comparison
        @threshold = threshold
        @color = color
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
        lines.concat(section("NOT COMPARABLE", comparison.not_comparable) { |row| not_comparable_lines(row) })
        lines.concat(summary_lines)
        lines.join("\n")
      end

      # Both the text and HTML renderers describe a score move the same way, so the wording
      # of "improved" versus "regressed" cannot drift between the two.
      def score_headline(row)
        parts = [score_relative(row), score_spread(row)].compact
        parts << "not gated" unless row[:gated]

        "#{row[:name]}  #{row[:baseline_mean]} -> #{row[:candidate_mean]}  #{format_delta(row[:delta])}  (#{parts.join(", ")})"
      end

      # --fail-on-regression is expressed relative to the baseline, so the absolute delta alone
      # cannot be checked against it: whether -1.0 clears a 0.25 threshold depends entirely on
      # what it is -1.0 of. nil when the baseline mean is zero and there is no fraction to take.
      def score_relative(row)
        baseline = row[:baseline_mean].to_f.abs
        return if baseline.zero?

        format("%+.1f%%", (row[:delta].to_f / baseline) * 100)
      end

      # A single observation has no standard deviation, so one side of the transition can be
      # absent while the other is real. The sd fragment is dropped only when neither side
      # has one; otherwise the missing side shows as "-".
      def score_spread(row)
        baseline = row[:baseline_stddev]
        candidate = row[:candidate_stddev]
        parts = ["n=#{row[:candidate_n]}"]
        parts << "sd #{baseline || "-"} -> #{candidate || "-"}" unless baseline.nil? && candidate.nil?

        parts.join(", ")
      end

      def format_delta(delta)
        delta.to_f.positive? ? "+#{delta}" : delta.to_s
      end

      def format_rate(rate)
        format("%.2f", rate.to_f)
      end

      # The threshold is restated as a percentage because it is relative to the baseline, and a
      # bare "0.25" next to a list of absolute deltas invites reading it as those deltas' units.
      def verdict
        return "no regression threshold set (--fail-on-regression)" if threshold.nil?

        gate = "--fail-on-regression #{threshold} (#{format("%g", threshold.to_f * 100)}% worse than baseline)"
        return "no regression beyond #{gate}" unless comparison.regressed?(threshold)

        count = comparison.regressions.count { |row| row[:magnitude].nil? || row[:magnitude] > threshold.to_f }
        "#{count} regression#{"s" if count != 1} beyond #{gate} (exit 1)"
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

        [
          "  baseline   #{side_line(baseline)}",
          "  candidate  #{side_line(candidate)}",
          "  judge      #{judge}",
          ""
        ]
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

      def not_comparable_lines(row)
        label = [row[:case_id] || "-", row[:expectation]].compact.join(" / ")
        ["  #{row[:eval_set]}  #{row[:description]}", "    #{label.ljust(20)} #{row[:present_in]}"]
      end

      def summary_lines
        baseline = comparison.to_h[:baseline]
        candidate = comparison.to_h[:candidate]

        lines = ["SUMMARY"]
        lines << "  evals passed          #{baseline[:passed_evals]}/#{baseline[:total_evals]} -> " \
          "#{candidate[:passed_evals]}/#{candidate[:total_evals]}"
        lines << "  expectations          #{baseline[:passed_expectations]}/#{baseline[:total_expectations]} -> " \
          "#{candidate[:passed_expectations]}/#{candidate[:total_expectations]}"

        comparison.score_moves.each do |row|
          lines << "  mean #{row[:name].ljust(16)} #{row[:baseline_mean]} -> #{row[:candidate_mean]}"
        end

        lines << "  total cost            $#{format("%.2f", baseline[:total_cost].to_f)} -> " \
          "$#{format("%.2f", candidate[:total_cost].to_f)}"
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
