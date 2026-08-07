# frozen_string_literal: true

module Raif
  module Evals
    # Diffs two eval run payloads. Deliberately free of Rails and of any provider call, so
    # "did this change make the product worse" can be answered without spending money.
    #
    # Results are matched on eval set, eval index, expectation description, and case id.
    # Matching per case rather than per eval is what makes a dataset run diffable, since a
    # model can improve on average while getting materially worse on one input.
    class Comparison
      attr_reader :baseline, :candidate, :baseline_label, :candidate_label

      def initialize(baseline:, candidate:, baseline_label: nil, candidate_label: nil)
        @baseline = baseline
        @candidate = candidate
        @baseline_label = baseline_label
        @candidate_label = candidate_label
      end

      def baseline_judge
        judge_model(baseline)
      end

      def candidate_judge
        judge_model(candidate)
      end

      # Scores from two different judges measure two different things, so this is a refusal
      # rather than a warning: a warning printed above a ranking is too easy to scroll past.
      def judge_mismatch?
        baseline_judge != candidate_judge
      end

      def new_failures
        eval_moves[:regressed]
      end

      def fixed
        eval_moves[:improved]
      end

      def score_moves
        @score_moves ||= build_score_moves
      end

      # Cases and expectations present on only one side. Surfaced rather than dropped: a
      # silently omitted case looks exactly like agreement.
      def not_comparable
        @not_comparable ||= build_not_comparable
      end

      # Every magnitude here is relative to the baseline rather than absolute, because the
      # quantities being gated are not in the same units: a pass rate is a fraction of runs, a
      # rubric score is a point on its own scale, and a latency is milliseconds. Comparing their
      # absolute deltas to one threshold means --fail-on-regression 0.25 asks for a quarter of
      # the runs in one row and a quarter of a millisecond in the next. Relative to baseline, it
      # asks one question everywhere: did something get more than 25% worse.
      #
      # Rows are drawn from every comparable eval rather than from new_failures, because which
      # section a row prints under and whether it contributes a regression are different
      # questions. An eval that fixed one expectation and broke another can come out ahead on
      # its overall rate and still be a trade, and the improvement would otherwise hide the loss.
      def regressions
        @regressions ||= begin
          from_evals = eval_rows.filter_map do |row|
            drop, baseline = worst_rate_drop(row)
            next if drop.nil?

            {
              kind: :pass_rate,
              magnitude: round(drop / baseline),
              absolute: round(drop),
              # Qualified by eval set, because the DSL does not enforce unique descriptions and
              # this label is all a script reading the JSON gets to identify the row by.
              label: "#{row[:eval_set]}  #{row[:description]} [#{row[:case_id] || "no case"}]"
            }
          end

          from_scores = score_moves.select { |row| row[:gated] && row[:regression] > 0 }.map do |row|
            { kind: :score, magnitude: relative_score_regression(row), absolute: row[:regression], label: row[:name] }
          end

          # An unbounded row (nil magnitude) sorts first: it is the worst thing in the list.
          (from_evals + from_scores).sort_by { |row| -(row[:magnitude] || Float::INFINITY) }
        end
      end

      # Rows whose regression cannot be expressed as a fraction because the baseline was zero.
      # "0 errors became 3" is a real regression with no ratio to take, so it is separated out
      # rather than dropped, and #regressed? treats it as exceeding any threshold.
      def unbounded_regressions
        regressions.select { |row| row[:magnitude].nil? }
      end

      # Float::INFINITY would be the literal magnitude of an unbounded regression, but this
      # value is exported to JSON, which cannot represent it. Ask #regressed? for the gate
      # decision; it accounts for the unbounded rows separately.
      def max_regression
        regressions.filter_map { |row| row[:magnitude] }.max || 0.0
      end

      def regressed?(threshold)
        return false if threshold.nil?

        unbounded_regressions.any? || max_regression > threshold.to_f
      end

      def to_h
        @to_h ||= {
          baseline: side_summary(baseline, baseline_label, baseline_units),
          candidate: side_summary(candidate, candidate_label, candidate_units),
          judge_mismatch: judge_mismatch?,
          new_failures: new_failures,
          fixed: fixed,
          score_moves: score_moves,
          not_comparable: not_comparable,
          regressions: regressions
        }
      end

    private

      def baseline_units
        @baseline_units ||= index_units(baseline)
      end

      def candidate_units
        @candidate_units ||= index_units(candidate)
      end

      def shared_keys
        @shared_keys ||= candidate_units.keys.select { |key| baseline_units.key?(key) }
      end

      # eval_index is the join key when present; older payloads predate it and fall back to
      # the description, which is the best available substitute.
      def index_units(payload)
        units = {}

        (payload["results"] || {}).each do |eval_set, results|
          Array(results).each do |result|
            key = [eval_set, result["eval_index"] || result["description"], result["case_id"]]

            unit = units[key] ||= {
              eval_set: eval_set,
              eval_index: result["eval_index"],
              description: result["description"],
              case_id: result["case_id"],
              runs: 0,
              passed: 0,
              expectations: {},
              scores: {}
            }

            unit[:runs] += 1
            unit[:passed] += 1 if result["passed"]

            Array(result["expectation_results"]).each do |expectation|
              tally = unit[:expectations][expectation["description"]] ||= { runs: 0, passed: 0 }
              tally[:runs] += 1
              tally[:passed] += 1 if expectation["status"].to_s == "passed"
            end

            Array(result["scores"]).each do |score|
              entry = unit[:scores][score["name"]] ||= {
                values: [],
                scale: score["scale"],
                higher_is_better: score.key?("higher_is_better") ? score["higher_is_better"] : true,
                gated: false
              }
              entry[:values] << score["value"].to_f
              entry[:gated] ||= !score["min"].nil? || !score["max"].nil?
            end
          end
        end

        units
      end

      # One row per eval both runs share, whether or not anything moved. #regressions reads
      # every row; #eval_moves classifies them into the report's sections.
      def eval_rows
        @eval_rows ||= shared_keys.map do |key|
          baseline_unit = baseline_units[key]
          candidate_unit = candidate_units[key]

          baseline_rate = pass_rate(baseline_unit)
          candidate_rate = pass_rate(candidate_unit)

          {
            eval_set: candidate_unit[:eval_set],
            eval_index: candidate_unit[:eval_index],
            description: candidate_unit[:description],
            case_id: candidate_unit[:case_id],
            baseline_rate: baseline_rate,
            candidate_rate: candidate_rate,
            delta: round(candidate_rate - baseline_rate),
            expectations: expectation_moves(baseline_unit, candidate_unit)
          }
        end
      end

      def eval_moves
        @eval_moves ||= begin
          # An eval whose rate held steady while a different expectation started failing is
          # reported as a new failure - one failure traded for another is not a fix. A trade
          # the rate came out ahead on reads better under FIXED, with the expectation that
          # dropped listed beneath it, and #regressions catches it either way.
          regressed, rest = eval_rows.partition do |row|
            row[:delta] < 0 || (row[:delta].zero? && row[:expectations].any? { |move| move[:delta] < 0 })
          end

          {
            regressed: regressed.sort_by { |row| [row[:delta], row[:eval_set].to_s, row[:case_id].to_s] },
            improved: rest.select { |row| row[:delta] > 0 }.sort_by { |row| [-row[:delta], row[:eval_set].to_s, row[:case_id].to_s] }
          }
        end
      end

      # The drop to gate on and the baseline it is relative to, or nil when nothing dropped.
      # Normally that is the eval's own rate; when the rate held steady or improved because a
      # fix absorbed a break, it is the expectation that broke, since one failure traded for
      # another is not a fix and the rate delta can no longer say so.
      #
      # The baseline is always positive here: a rate that dropped cannot have started at zero,
      # so the caller's division is always defined.
      def worst_rate_drop(row)
        return [-row[:delta], row[:baseline_rate]] if row[:delta] < 0

        worst = row[:expectations].min_by { |move| move[:delta] }
        return if worst.nil? || !worst[:delta].negative?

        [-worst[:delta], worst[:baseline_rate]]
      end

      # nil when the baseline mean is zero, which has no fraction to take. Callers treat that as
      # an unbounded regression rather than as no regression - see #unbounded_regressions.
      def relative_score_regression(row)
        baseline = row[:baseline_mean].to_f.abs
        return if baseline.zero?

        round(row[:regression] / baseline)
      end

      def expectation_moves(baseline_unit, candidate_unit)
        shared = candidate_unit[:expectations].keys.select { |description| baseline_unit[:expectations].key?(description) }

        shared.filter_map do |description|
          baseline_rate = tally_rate(baseline_unit[:expectations][description])
          candidate_rate = tally_rate(candidate_unit[:expectations][description])
          delta = round(candidate_rate - baseline_rate)
          next if delta.zero?

          { description: description, baseline_rate: baseline_rate, candidate_rate: candidate_rate, delta: delta }
        end.sort_by { |move| move[:delta] }
      end

      def build_score_moves
        baseline_scores = index_scores(baseline_units)
        candidate_scores = index_scores(candidate_units)

        candidate_scores.filter_map do |key, candidate_score|
          baseline_score = baseline_scores[key]
          next if baseline_score.nil?

          baseline_values, candidate_values = comparable_score_values(baseline_score, candidate_score)

          baseline_mean = Statistics.mean(baseline_values)
          candidate_mean = Statistics.mean(candidate_values)
          next if baseline_mean.nil? || candidate_mean.nil?

          delta = round(candidate_mean - baseline_mean)
          next if delta.zero?

          higher_is_better = candidate_score[:higher_is_better]

          {
            eval_set: candidate_score[:eval_set],
            eval_index: candidate_score[:eval_index],
            description: candidate_score[:description],
            name: candidate_score[:name],
            scale: candidate_score[:scale],
            higher_is_better: higher_is_better,
            gated: candidate_score[:gated] || baseline_score[:gated],
            baseline_mean: round(baseline_mean),
            candidate_mean: round(candidate_mean),
            delta: delta,
            regression: round(higher_is_better ? -delta : delta),
            baseline_n: baseline_values.count,
            candidate_n: candidate_values.count,
            baseline_stddev: round(Statistics.stddev(baseline_values)),
            candidate_stddev: round(Statistics.stddev(candidate_values)),
            per_case: score_per_case_moves(baseline_score, candidate_score)
          }
        end.sort_by { |row| -row[:regression] }
      end

      # When both sides carry a per-case breakdown (a dataset score), compare only the cases
      # they share: a candidate sampled down to a subset must not look improved merely because
      # the cases it dropped were the low-scoring ones. If the shared set is empty the means
      # come back nil and the move is omitted. Non-dataset scores have no per-case breakdown
      # and compare their full value lists.
      def comparable_score_values(baseline_score, candidate_score)
        return [baseline_score[:values], candidate_score[:values]] if baseline_score[:per_case].empty? || candidate_score[:per_case].empty?

        shared = baseline_score[:per_case].keys & candidate_score[:per_case].keys
        [
          shared.flat_map { |case_id| baseline_score[:per_case][case_id] },
          shared.flat_map { |case_id| candidate_score[:per_case][case_id] }
        ]
      end

      def index_scores(units)
        index = {}

        units.each_value do |unit|
          unit[:scores].each do |name, entry|
            key = [unit[:eval_set], unit[:eval_index] || unit[:description], name]

            aggregate = index[key] ||= {
              eval_set: unit[:eval_set],
              eval_index: unit[:eval_index],
              description: unit[:description],
              name: name,
              scale: entry[:scale],
              higher_is_better: entry[:higher_is_better],
              gated: false,
              values: [],
              per_case: {}
            }

            aggregate[:values].concat(entry[:values])
            aggregate[:gated] ||= entry[:gated]
            aggregate[:per_case][unit[:case_id]] = entry[:values] if unit[:case_id]
          end
        end

        index
      end

      def score_per_case_moves(baseline_score, candidate_score)
        candidate_score[:per_case].filter_map do |case_id, candidate_values|
          baseline_values = baseline_score[:per_case][case_id]
          next if baseline_values.nil?

          baseline_mean = Statistics.mean(baseline_values)
          candidate_mean = Statistics.mean(candidate_values)

          {
            case_id: case_id,
            baseline_mean: round(baseline_mean),
            candidate_mean: round(candidate_mean),
            delta: round(candidate_mean - baseline_mean)
          }
        end
      end

      def build_not_comparable
        rows = (baseline_units.keys - candidate_units.keys).map { |key| unmatched_row(baseline_units[key], "baseline only") }
        rows += (candidate_units.keys - baseline_units.keys).map { |key| unmatched_row(candidate_units[key], "candidate only") }

        shared_keys.each do |key|
          baseline_unit = baseline_units[key]
          candidate_unit = candidate_units[key]

          (baseline_unit[:expectations].keys - candidate_unit[:expectations].keys).each do |description|
            rows << unmatched_row(baseline_unit, "baseline only").merge(expectation: description)
          end

          (candidate_unit[:expectations].keys - baseline_unit[:expectations].keys).each do |description|
            rows << unmatched_row(candidate_unit, "candidate only").merge(expectation: description)
          end
        end

        rows
      end

      def unmatched_row(unit, present_in)
        {
          eval_set: unit[:eval_set],
          eval_index: unit[:eval_index],
          description: unit[:description],
          case_id: unit[:case_id],
          present_in: present_in
        }
      end

      def side_summary(payload, label, units)
        summary = payload["summary"] || {}
        configuration = payload["configuration"] || {}

        {
          label: label,
          model: configuration["default_llm_model_key"],
          judge: configuration["evals_default_llm_judge_model_key"],
          repeats: configuration["repeats"],
          run_at: payload["run_at"],
          evals: units.map { |key, _unit| key[0, 2] }.uniq.count,
          cases: units.filter_map { |_key, unit| unit[:case_id] }.uniq.count,
          runs: units.sum { |_key, unit| unit[:runs] },
          passed_evals: summary["passed_evals"],
          total_evals: summary["total_evals"],
          passed_expectations: summary["passed_expectations"],
          total_expectations: summary["total_expectations"],
          total_cost: summary["total_cost"]
        }
      end

      def judge_model(payload)
        (payload["configuration"] || {})["evals_default_llm_judge_model_key"]
      end

      def pass_rate(unit)
        tally_rate(unit)
      end

      def tally_rate(tally)
        return 0.0 if tally[:runs].zero?

        round(tally[:passed].to_f / tally[:runs])
      end

      def round(value)
        value&.round(4)
      end
    end
  end
end
