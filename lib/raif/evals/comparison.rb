# frozen_string_literal: true

module Raif
  module Evals
    # Diffs two eval run payloads. Deliberately free of Rails and of any provider call, so it
    # needs no database, API key, or spend.
    #
    # Results are matched on eval id, case id, and expectation description. Matching per case is
    # what makes a dataset run diffable: a model can improve on average while getting materially
    # worse on one input.
    class Comparison
      # Family-wise significance level for the regression gate: the chance the whole comparison
      # reports at least one regression that was only noise. Per-row levels are this divided by
      # the number of rows tested - see #significant_regressions.
      FAMILY_WISE_ALPHA = 0.05

      # The share of runs either side may lose to errors before the regression gate refuses to
      # decide - see #error_rate_unreliable?. Loose enough that one flaky call in a thirty-run
      # suite does not block a gate, tight enough that a provider incident does.
      MAX_GATE_ERROR_RATE = 0.05

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

      # Scores from two different judges measure two different things, so callers refuse to
      # compare rather than warn.
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

      # Cases and expectations present on only one side, plus the ones a side errored out of
      # entirely. Surfaced rather than dropped: a silently omitted case looks exactly like
      # agreement.
      def not_comparable
        @not_comparable ||= build_not_comparable
      end

      # How often each side raised instead of producing a measurement. Reported on its own rather
      # than through the pass rates, which now exclude errors: a run that got worse and a run that
      # got flakier need different responses, and folding them together tells the reader neither.
      def error_moves
        @error_moves ||= build_error_moves
      end

      def baseline_error_rate
        @baseline_error_rate ||= overall_error_rate(baseline_units)
      end

      def candidate_error_rate
        @candidate_error_rate ||= overall_error_rate(candidate_units)
      end

      # Errors are out of the pass-rate denominator, which handles the first-order problem. What
      # is left is selection: if the runs that errored were not a random sample of the runs - the
      # long inputs are the ones that time out - the surviving denominator is a biased one, and
      # the bias scales with how many were lost. Past this rate the comparison is not a sound
      # basis for a pass/fail, so callers refuse to gate on it rather than gate on it badly.
      #
      # @param max_error_rate [Numeric] the fraction of runs allowed to error on either side.
      def error_rate_unreliable?(max_error_rate: MAX_GATE_ERROR_RATE)
        [baseline_error_rate, candidate_error_rate].max > max_error_rate.to_f
      end

      # Every regression either run shows, each with two independent halves: how big it is
      # (#magnitude, the effect size) and how sure we can be it is not noise (#p_value).
      # #regressed? demands both, because either alone gates badly - a threshold on point
      # estimates fires on run-to-run variation until someone disables it, and a significance
      # test with no floor on size fails a run over a rounding error it happened to measure
      # precisely.
      #
      # Magnitudes are relative to the baseline, not absolute: a pass rate, a rubric score, and
      # a latency are not in the same units, so one absolute threshold would mean a quarter of
      # the runs in one row and a quarter of a millisecond in the next. Relative,
      # --fail-on-regression asks the same question everywhere: did this get more than N% worse.
      #
      # Rows come from every comparable eval, not just new_failures: an eval that fixed one
      # expectation and broke another can come out ahead on its rate and still be a trade.
      def regressions
        # An unbounded row (nil magnitude) sorts first: it is the worst thing in the list.
        @regressions ||= (pass_rate_regressions + score_regressions).sort_by { |row| -(row[:magnitude] || Float::INFINITY) }
      end

      # Rows with no fraction to take because the baseline was zero. "0 errors became 3" is
      # still a regression, so it is separated out rather than dropped and #regressed? treats
      # it as exceeding any threshold.
      def unbounded_regressions
        regressions.select { |row| row[:magnitude].nil? }
      end

      # Excludes unbounded regressions, whose magnitude would be Float::INFINITY and cannot be
      # exported to JSON. Ask #regressed? for the gate decision, which accounts for both.
      def max_regression
        regressions.filter_map { |row| row[:magnitude] }.max || 0.0
      end

      # The rows big enough to gate on, before asking whether they are distinguishable from
      # noise. Everything below is derived from this set rather than from #regressions, so the
      # evidence bar is only ever applied to rows that already cleared the size bar.
      def candidate_regressions(threshold)
        return [] if threshold.nil?

        regressions.select { |row| row[:magnitude].nil? || row[:magnitude] > threshold.to_f }
      end

      # Candidates whose move cannot be tested at all: a score on an eval with no dataset, where
      # the only unit is the repeat and repeat 3 of one run is not the counterpart of repeat 3 of
      # the other. Reported rather than silently passed - a gate that cannot answer the question
      # it was asked has to say so, or a run with a real regression exits 0 looking green.
      def unverifiable_regressions(threshold)
        candidate_regressions(threshold).select { |row| row[:p_value].nil? }
      end

      # Candidates that cleared both bars. The per-row level is the family-wise alpha divided by
      # the number of candidates (Bonferroni): the gate fails if ANY row is significant, so
      # testing each at 0.05 would fail one run in every three of a 20-row suite on noise alone -
      # turning a fix for a flaky gate into a flakier one. Dividing by the candidate count rather
      # than by every row in the report keeps the correction as loose as it can honestly be,
      # since the size threshold does not depend on the spread.
      def significant_regressions(threshold, alpha: FAMILY_WISE_ALPHA)
        candidates = candidate_regressions(threshold)
        return candidates if evidence_waived?(alpha)
        return [] if candidates.empty?

        per_row_alpha = alpha.to_f / candidates.count
        candidates.select { |row| row[:p_value] && row[:p_value] <= per_row_alpha }
      end

      # @param threshold [Numeric, nil] the effect size gate, as a fraction of baseline. nil
      #   never fails.
      # @param alpha [Numeric] family-wise significance level. 1 or greater waives the evidence
      #   requirement entirely, gating on point estimates alone - which is what someone with a
      #   three-case dataset has to do, since three matched pairs cannot reach any conventional
      #   level however large the regression.
      def regressed?(threshold, alpha: FAMILY_WISE_ALPHA)
        return false if threshold.nil?

        significant_regressions(threshold, alpha: alpha).any?
      end

      # True when the gate was asked a question it has no evidence to answer: something moved
      # past the threshold, nothing that moved could be tested. Distinct from "nothing regressed",
      # and the caller is expected to report it rather than exit 0 on it.
      def insufficient_evidence?(threshold, alpha: FAMILY_WISE_ALPHA)
        return false if threshold.nil? || evidence_waived?(alpha)

        candidates = candidate_regressions(threshold)
        candidates.any? && candidates.all? { |row| row[:p_value].nil? }
      end

      def to_h
        @to_h ||= {
          baseline: side_summary(baseline, baseline_label, baseline_units),
          candidate: side_summary(candidate, candidate_label, candidate_units),
          judge_mismatch: judge_mismatch?,
          new_failures: new_failures,
          fixed: fixed,
          score_moves: score_moves,
          error_moves: error_moves,
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

      # Shared keys minus the ones where a side has no measured run left to compare. A case whose
      # every run errored produced no rate, and inventing one - in either direction - would let an
      # outage decide the gate. It is reported under NOT COMPARABLE instead, alongside the cases
      # that only one side ran, which is the same problem: a missing measurement.
      def comparable_keys
        @comparable_keys ||= shared_keys.reject { |key| errored_out?(key) }
      end

      def errored_out?(key)
        measured_runs(baseline_units[key]).zero? || measured_runs(candidate_units[key]).zero?
      end

      # Keyed on the eval's id, which survives edits to the file that declares it and already
      # carries its eval set, so an eval that moved still matches its counterpart.
      def index_units(payload)
        units = {}

        (payload["results"] || {}).each do |eval_set, results|
          Array(results).each do |result|
            key = [result["eval_id"], result["case_id"]]

            unit = units[key] ||= {
              eval_set: eval_set,
              eval_id: result["eval_id"],
              eval_index: result["eval_index"],
              description: result["description"],
              case_id: result["case_id"],
              runs: 0,
              passed: 0,
              errored: 0,
              expectations: {},
              scores: {}
            }

            unit[:runs] += 1
            unit[:passed] += 1 if result["passed"]
            # Derived from the expectation statuses rather than read from result["errored"],
            # which runs written before this distinction existed do not carry. The statuses they
            # do carry, so an old results file compares on the same terms as a new one.
            unit[:errored] += 1 if Array(result["expectation_results"]).any? { |e| e["status"].to_s == "error" }

            Array(result["expectation_results"]).each do |expectation|
              tally = unit[:expectations][expectation["description"]] ||= { runs: 0, passed: 0, errored: 0 }
              tally[:runs] += 1
              tally[:passed] += 1 if expectation["status"].to_s == "passed"
              tally[:errored] += 1 if expectation["status"].to_s == "error"
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
        @eval_rows ||= comparable_keys.map do |key|
          baseline_unit = baseline_units[key]
          candidate_unit = candidate_units[key]

          baseline_rate = pass_rate(baseline_unit)
          candidate_rate = pass_rate(candidate_unit)

          {
            eval_set: candidate_unit[:eval_set],
            eval_id: candidate_unit[:eval_id],
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
          # An eval whose rate held steady while a different expectation started failing is a
          # new failure: one failure traded for another is not a fix. A trade the rate came out
          # ahead on reads better under FIXED, and #regressions catches it either way.
          regressed, rest = eval_rows.partition do |row|
            row[:delta] < 0 || (row[:delta].zero? && row[:expectations].any? { |move| move[:delta] < 0 })
          end

          {
            regressed: regressed.sort_by { |row| [row[:delta], row[:eval_set].to_s, row[:case_id].to_s] },
            improved: rest.select { |row| row[:delta] > 0 }.sort_by { |row| [-row[:delta], row[:eval_set].to_s, row[:case_id].to_s] }
          }
        end
      end

      def evidence_waived?(alpha)
        alpha.nil? || alpha.to_f >= 1.0
      end

      # Gate rows for pass rates, one per eval rather than one per case. A dataset eval's cases
      # are the matched pairs the evidence test counts, so gating each case on its own would ask
      # for a verdict from a single draw - which is the noise the gate exists to filter, not the
      # signal it is looking for. Per-case detail stays in #new_failures, where it is reported
      # rather than acted on.
      def pass_rate_regressions
        comparable_keys.group_by { |key| key.first }.filter_map do |_eval_id, keys|
          pairs = keys.map { |key| [baseline_units[key], candidate_units[key]] }

          drop = eval_rate_drop(pairs) || worst_expectation_drop(pairs)
          next if drop.nil?

          unit = candidate_units[keys.first]

          {
            kind: :pass_rate,
            magnitude: round(drop[:absolute] / drop[:baseline]),
            absolute: round(drop[:absolute]),
            # Qualified by eval set: descriptions are not unique, and this label is all a script
            # reading the JSON has to identify the row by. The expectation joins it when the drop
            # came from one, since the eval's own rate will not show it.
            label: [unit[:eval_set], unit[:description], drop[:expectation]].compact.join("  "),
            eval_set: unit[:eval_set],
            eval_id: unit[:eval_id],
            description: unit[:description],
            expectation: drop[:expectation],
            cases: pairs.count
          }.merge(rate_evidence(drop)).compact
        end
      end

      # The eval's own mean pass rate across its cases, when that is what dropped. The baseline is
      # always positive here, since a rate that dropped cannot have started at zero, so the
      # caller's division is defined.
      def eval_rate_drop(pairs)
        deltas = pairs.map { |baseline_unit, candidate_unit| tally_rate(candidate_unit) - tally_rate(baseline_unit) }
        mean_delta = Statistics.mean(deltas)
        return unless mean_delta&.negative?

        {
          absolute: -mean_delta,
          baseline: Statistics.mean(pairs.map { |baseline_unit, _candidate| tally_rate(baseline_unit) }),
          deltas: deltas,
          tallies: pooled_tallies(pairs)
        }
      end

      # When a fix absorbed a break, the eval's rate can no longer say so, and the expectation
      # that broke is what the gate has to read instead. Averaged over every case the expectation
      # appears in on both sides, including the ones where it did not move: a mean over only the
      # cases that moved would report a bigger drop than there was, and the tied cases are exactly
      # what the sign test then discards.
      def worst_expectation_drop(pairs)
        descriptions = pairs.flat_map { |baseline_unit, candidate_unit| baseline_unit[:expectations].keys & candidate_unit[:expectations].keys }.uniq

        descriptions.filter_map do |description|
          # Both sides need a measured run of the expectation, not merely a record of it: an
          # expectation that only ever errored has no rate, and tally_rate returns nil there.
          present = pairs.select do |baseline_unit, candidate_unit|
            [baseline_unit, candidate_unit].all? do |unit|
              tally = unit[:expectations][description]
              tally && measured_runs(tally).positive?
            end
          end

          deltas = present.map do |baseline_unit, candidate_unit|
            tally_rate(candidate_unit[:expectations][description]) - tally_rate(baseline_unit[:expectations][description])
          end

          mean_delta = Statistics.mean(deltas)
          next unless mean_delta&.negative?

          {
            absolute: -mean_delta,
            baseline: Statistics.mean(present.map { |baseline_unit, _c| tally_rate(baseline_unit[:expectations][description]) }),
            deltas: deltas,
            expectation: description,
            tallies: pooled_tallies(present, description)
          }
        end.max_by { |drop| drop[:absolute] }
      end

      # Matched cases when there are any: two runs over the same dataset are paired by case id, and
      # a paired test over N cases sees a consistent move that two independent means of the same
      # numbers cannot separate from spread. With a single case - or none, on an eval with no
      # dataset - the repeats are all there is and they are not paired, so the two rates go to an
      # exact test on their counts instead. At one repeat a side that test cannot reach any level,
      # which is the correct answer to "did this one draw prove anything".
      def rate_evidence(drop)
        deltas = drop[:deltas]

        if deltas.count >= 2
          worsened = deltas.count(&:negative?)
          improved = deltas.count(&:positive?)

          return {
            evidence: :paired_cases,
            pairs: worsened + improved,
            worsened: worsened,
            improved: improved,
            p_value: round_p(Statistics.sign_test(worsened: worsened, improved: improved))
          }
        end

        baseline_tally, candidate_tally = drop[:tallies]
        p_value = Statistics.fisher_exact_p(
          baseline_passed: baseline_tally[:passed],
          baseline_total: baseline_tally[:runs],
          candidate_passed: candidate_tally[:passed],
          candidate_total: candidate_tally[:runs]
        )

        { evidence: p_value ? :repeats : :none, pairs: 0, p_value: round_p(p_value) }
      end

      def score_regressions
        score_moves.select { |row| row[:gated] && row[:regression] > 0 }.map do |row|
          {
            kind: :score,
            magnitude: relative_score_regression(row),
            absolute: row[:regression],
            label: row[:name],
            eval_set: row[:eval_set],
            eval_id: row[:eval_id],
            description: row[:description]
          }.merge(score_evidence(row))
        end
      end

      # A score's matched unit is the dataset case. Without a dataset there is nothing to pair -
      # the repeats are independent draws on each side, and a continuous score has no exact
      # two-sample test at the counts these runs produce - so the row is left unverifiable rather
      # than handed to something that would invent precision it does not have.
      def score_evidence(row)
        deltas = row[:per_case].map { |per_case| per_case[:delta] }
        return { evidence: :none, pairs: 0, p_value: nil } if deltas.count < 2

        # Direction rather than sign: a max-gated score regresses upward.
        worsened = deltas.count { |delta| row[:higher_is_better] ? delta.negative? : delta.positive? }
        improved = deltas.count { |delta| row[:higher_is_better] ? delta.positive? : delta.negative? }

        {
          evidence: :paired_cases,
          pairs: worsened + improved,
          worsened: worsened,
          improved: improved,
          p_value: round_p(Statistics.sign_test(worsened: worsened, improved: improved))
        }
      end

      # Pooled counts for both sides, for the unpaired path. Takes the expectation's own tallies
      # when a description is given, the eval's own when it is not.
      def pooled_tallies(pairs, description = nil)
        [0, 1].map do |side|
          tallies = pairs.map do |pair|
            description ? pair[side][:expectations][description] : pair[side]
          end

          # measured_runs, so the exact test's denominator matches the rates it is testing.
          { passed: tallies.sum { |tally| tally[:passed] }, runs: tallies.sum { |tally| measured_runs(tally) } }
        end
      end

      # Rounded further than the other figures here because a Bonferroni-adjusted level goes
      # several places into the tail, and 4 would flatten the difference between "significant" and
      # "not" for a suite with more than a handful of candidate rows.
      def round_p(value)
        value&.round(6)
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
          # nil on either side means one of them only errored, so there is no move to report.
          next if baseline_rate.nil? || candidate_rate.nil?

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
            eval_id: candidate_score[:eval_id],
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
            baseline_stddev: round(Statistics.stddev(spread_values(baseline_score, candidate_score))),
            candidate_stddev: round(Statistics.stddev(spread_values(candidate_score, baseline_score))),
            spread_n: spread_values(candidate_score, baseline_score).count,
            per_case: score_per_case_moves(baseline_score, candidate_score)
          }
        end.sort_by { |row| -row[:regression] }
      end

      # The unit the reported spread describes: per-case means for a dataset score, raw values
      # without one - never the pooled values the mean is taken over, for the reason
      # Raif::Evals::Run#score_summaries gives where it picks the same unit.
      #
      # Restricted to the shared cases for the same reason #comparable_score_values is: a candidate
      # sampled down to a subset must not have its spread measured over a different set of inputs
      # than the baseline it is printed next to.
      def spread_values(score, other)
        return score[:values] if score[:per_case].empty? || other[:per_case].empty?

        shared = score[:per_case].keys & other[:per_case].keys
        shared.filter_map { |case_id| Statistics.mean(score[:per_case][case_id]) }
      end

      # When both sides carry a per-case breakdown (a dataset score), compare only the cases
      # they share: a candidate sampled down to a subset must not look improved merely because
      # the cases it dropped were the low-scoring ones. An empty shared set yields nil means,
      # and the move is omitted.
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
            key = [unit[:eval_id], name]

            aggregate = index[key] ||= {
              eval_set: unit[:eval_set],
              eval_id: unit[:eval_id],
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

      # One row per eval both runs share, kept only when a side actually errored: a table of
      # 0.00 -> 0.00 rows would bury the one eval that went flaky. Grouped per eval rather than
      # per case for the same reason the gate is - a single case's error count is one draw.
      def build_error_moves
        shared_keys.group_by { |key| key.first }.filter_map do |_eval_id, keys|
          baseline_errored = keys.sum { |key| baseline_units[key][:errored] }
          candidate_errored = keys.sum { |key| candidate_units[key][:errored] }
          next if baseline_errored.zero? && candidate_errored.zero?

          baseline_runs = keys.sum { |key| baseline_units[key][:runs] }
          candidate_runs = keys.sum { |key| candidate_units[key][:runs] }
          baseline_rate = round(baseline_errored.to_f / baseline_runs)
          candidate_rate = round(candidate_errored.to_f / candidate_runs)
          unit = candidate_units[keys.first]

          {
            eval_set: unit[:eval_set],
            eval_id: unit[:eval_id],
            eval_index: unit[:eval_index],
            description: unit[:description],
            baseline_errored: baseline_errored,
            baseline_runs: baseline_runs,
            baseline_rate: baseline_rate,
            candidate_errored: candidate_errored,
            candidate_runs: candidate_runs,
            candidate_rate: candidate_rate,
            delta: round(candidate_rate - baseline_rate)
          }
        end.sort_by { |row| -row[:delta] }
      end

      # Over every unit on the side, not only the shared ones: the question the gate asks with it
      # is whether that run was healthy enough to draw a conclusion from, which the cases the
      # other run happens to have does not change.
      def overall_error_rate(units)
        runs = units.sum { |_key, unit| unit[:runs] }
        return 0.0 if runs.zero?

        round(units.sum { |_key, unit| unit[:errored] }.to_f / runs)
      end

      def build_not_comparable
        rows = (baseline_units.keys - candidate_units.keys).map { |key| unmatched_row(baseline_units[key], "baseline only") }
        rows += (candidate_units.keys - baseline_units.keys).map { |key| unmatched_row(candidate_units[key], "candidate only") }

        shared_keys.each do |key|
          baseline_unit = baseline_units[key]
          candidate_unit = candidate_units[key]

          next rows << errored_out_row(key) if errored_out?(key)

          (baseline_unit[:expectations].keys - candidate_unit[:expectations].keys).each do |description|
            rows << unmatched_row(baseline_unit, "baseline only").merge(expectation: description)
          end

          (candidate_unit[:expectations].keys - baseline_unit[:expectations].keys).each do |description|
            rows << unmatched_row(candidate_unit, "candidate only").merge(expectation: description)
          end
        end

        rows
      end

      # The description travels with the id: a NOT COMPARABLE row carrying only a digest tells a
      # reader nothing, where the description usually shows them the eval they reworded.
      #
      # reason is what the report prints. present_in is kept beside it because it is the field a
      # script reading the JSON already keys on, and it stays true of these rows.
      def unmatched_row(unit, present_in)
        {
          eval_set: unit[:eval_set],
          eval_id: unit[:eval_id],
          eval_index: unit[:eval_index],
          description: unit[:description],
          case_id: unit[:case_id],
          present_in: present_in,
          reason: present_in
        }
      end

      # Both runs have the case; one of them has nothing left to compare after its errors. Named
      # by which side, and with the count, because the two readings differ: a candidate that
      # errored out is usually the run to re-do, where a baseline that did means the comparison
      # never had a reference point.
      def errored_out_row(key)
        sides = { "baseline" => baseline_units[key], "candidate" => candidate_units[key] }
        out = sides.select { |_side, unit| measured_runs(unit).zero? }
        reason = out.map { |side, unit| "#{side}: all #{unit[:runs]} run#{"s" unless unit[:runs] == 1} errored" }.join(", ")

        unmatched_row(candidate_units[key], "both").merge(reason: reason)
      end

      def side_summary(payload, label, units)
        summary = payload["summary"] || {}
        configuration = payload["configuration"] || {}

        {
          label: label,
          model: configuration["default_llm_model_key"],
          judge: judge_model(payload),
          repeats: configuration["repeats"],
          run_at: payload["run_at"],
          evals: units.map { |key, _unit| key.first }.uniq.count,
          cases: units.filter_map { |_key, unit| unit[:case_id] }.uniq.count,
          runs: units.sum { |_key, unit| unit[:runs] },
          passed_evals: summary["passed_evals"],
          total_evals: summary["total_evals"],
          passed_expectations: summary["passed_expectations"],
          total_expectations: summary["total_expectations"],
          # Counted off the units rather than read from summary["errored_evals"], which runs
          # written before that key existed do not have. The expectation statuses they do have.
          errored_evals: units.sum { |_key, unit| unit[:errored] },
          error_rate: overall_error_rate(units),
          total_cost: summary["total_cost"]
        }
      end

      # The judge a run resolved, not the one it configured: a run that configured nothing was
      # graded by its own model under test, so reading the setting made two runs graded by two
      # different models look like they shared one ruler.
      def judge_model(payload)
        (payload["configuration"] || {})["judge_model_key"]
      end

      def pass_rate(unit)
        tally_rate(unit)
      end

      # Errored runs come out of the denominator: they measured nothing, and counting them as
      # misses would let a rate-limited afternoon read as a quality regression. nil when nothing
      # was measured at all, which callers route to NOT COMPARABLE rather than to zero.
      def tally_rate(tally)
        measured = measured_runs(tally)
        return if measured.zero?

        round(tally[:passed].to_f / measured)
      end

      def measured_runs(tally)
        tally[:runs] - tally[:errored].to_i
      end

      def round(value)
        value&.round(4)
      end
    end
  end
end
