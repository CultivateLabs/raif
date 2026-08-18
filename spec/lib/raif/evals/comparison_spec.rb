# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::Comparison do
  # eval_id defaults off eval_index only so a fixture wanting two eval blocks gets two ids. A real
  # id is derived from the eval set and description, not position - see "keyed on eval id" below.
  def eval_result(description: "produces expected output", eval_id: nil, eval_index: 0, case_id: nil, expectations: {}, scores: [])
    {
      "description" => description,
      "eval_id" => eval_id || "Set#eval-#{eval_index}",
      "eval_index" => eval_index,
      "case_id" => case_id,
      "passed" => expectations.values.all?,
      "expectation_results" => expectations.map do |expectation_description, passed|
        { "description" => expectation_description, "status" => passed ? "passed" : "failed" }
      end,
      "scores" => scores
    }
  end

  def score(name:, value:, min: nil, max: nil, higher_is_better: true)
    { "name" => name, "value" => value, "higher_is_better" => higher_is_better, "min" => min, "max" => max }.compact
  end

  def payload(results, judge: "anthropic_claude_5_sonnet", model: "gpt_a", cost: 1.10)
    {
      "run_at" => "2026-08-04T18:02:16Z",
      "configuration" => {
        "default_llm_model_key" => model,
        "evals_default_llm_judge_model_key" => judge,
        "judge_model_key" => judge,
        "repeats" => 2
      },
      "results" => results,
      "summary" => {
        "passed_evals" => results.values.flatten.count { |r| r["passed"] },
        "total_evals" => results.values.flatten.count,
        "passed_expectations" => results.values.flatten.sum { |r| r["expectation_results"].count { |e| e["status"] == "passed" } },
        "total_expectations" => results.values.flatten.sum { |r| r["expectation_results"].count },
        "total_cost" => cost
      }
    }
  end

  describe "keyed on eval id" do
    # The bug the id exists to remove: keyed on position, adding an eval above this one joined it
    # against whatever then sat at its old index.
    it "matches an eval whose position in its file moved between the two runs" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(eval_id: "Set#summarizes-abc123", eval_index: 0, case_id: "a",
          expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(eval_id: "Set#summarizes-abc123", eval_index: 3, case_id: "a",
          expectations: { "e" => false })] })
      )

      expect(comparison.not_comparable).to be_empty
      expect(comparison.new_failures.map { |row| row[:eval_id] }).to eq(["Set#summarizes-abc123"])
    end

    it "keeps two evals that ran the same case apart" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(eval_id: "Set#first-abc123", case_id: "a", expectations: { "e" => true }),
          eval_result(eval_id: "Set#second-def456", case_id: "a", expectations: { "e" => true })
        ] }),
        candidate: payload({ "Set" => [
          eval_result(eval_id: "Set#first-abc123", case_id: "a", expectations: { "e" => false }),
          eval_result(eval_id: "Set#second-def456", case_id: "a", expectations: { "e" => true })
        ] })
      )

      expect(comparison.new_failures.map { |row| row[:eval_id] }).to eq(["Set#first-abc123"])
      expect(comparison.to_h[:candidate][:evals]).to eq(2)
    end

    # A digest on its own tells a reader nothing about which eval stopped matching.
    it "reports the description alongside an id present in only one run" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(description: "old wording", eval_id: "Set#old-wording-abc123",
          expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(description: "new wording", eval_id: "Set#new-wording-def456",
          expectations: { "e" => true })] })
      )

      expect(comparison.not_comparable).to contain_exactly(
        hash_including(eval_id: "Set#old-wording-abc123", description: "old wording", present_in: "baseline only"),
        hash_including(eval_id: "Set#new-wording-def456", description: "new wording", present_in: "candidate only")
      )
    end
  end

  describe "pass rate classification" do
    let(:comparison) do
      described_class.new(
        baseline: payload({ "SummarizationEvalSet" => [
          eval_result(case_id: "press-release", expectations: { "is between 100 and 1000 words" => true }),
          eval_result(case_id: "press-release", expectations: { "is between 100 and 1000 words" => true }),
          eval_result(case_id: "stub-document", expectations: { "is between 100 and 1000 words" => false }),
          eval_result(case_id: "stub-document", expectations: { "is between 100 and 1000 words" => false })
        ] }),
        candidate: payload({ "SummarizationEvalSet" => [
          eval_result(case_id: "press-release", expectations: { "is between 100 and 1000 words" => true }),
          eval_result(case_id: "press-release", expectations: { "is between 100 and 1000 words" => false }),
          eval_result(case_id: "stub-document", expectations: { "is between 100 and 1000 words" => true }),
          eval_result(case_id: "stub-document", expectations: { "is between 100 and 1000 words" => true })
        ] })
      )
    end

    it "reports the case whose rate dropped, with the expectation that moved" do
      expect(comparison.new_failures.count).to eq(1)

      failure = comparison.new_failures.first
      expect(failure).to include(
        eval_set: "SummarizationEvalSet",
        case_id: "press-release",
        baseline_rate: 1.0,
        candidate_rate: 0.5,
        delta: -0.5
      )
      expect(failure[:expectations]).to eq([
        { description: "is between 100 and 1000 words", baseline_rate: 1.0, candidate_rate: 0.5, delta: -0.5 }
      ])
    end

    it "reports the case whose rate rose" do
      expect(comparison.fixed.count).to eq(1)
      expect(comparison.fixed.first).to include(case_id: "stub-document", baseline_rate: 0.0, candidate_rate: 1.0, delta: 1.0)
    end

    it "leaves unchanged cases out of both sections" do
      unchanged = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true })] })
      )

      expect(unchanged.new_failures).to be_empty
      expect(unchanged.fixed).to be_empty
    end

    # One failure traded for another is not a fix, even though the eval rate did not move.
    it "flags an eval whose rate held steady while a different expectation started failing" do
      traded = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => false, "second" => true })] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => true, "second" => false })] })
      )

      expect(traded.new_failures.count).to eq(1)
      expect(traded.new_failures.first[:delta]).to eq(0.0)
      expect(traded.new_failures.first[:expectations].map { |move| move[:description] }).to include("second")
    end

    it "sorts the largest regression first" do
      sorted = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(eval_index: 0, case_id: "small", expectations: { "e" => true }),
          eval_result(eval_index: 0, case_id: "small", expectations: { "e" => false }),
          eval_result(eval_index: 1, case_id: "big", expectations: { "e" => true })
        ] }),
        candidate: payload({ "Set" => [
          eval_result(eval_index: 0, case_id: "small", expectations: { "e" => false }),
          eval_result(eval_index: 0, case_id: "small", expectations: { "e" => false }),
          eval_result(eval_index: 1, case_id: "big", expectations: { "e" => false })
        ] })
      )

      expect(sorted.new_failures.map { |row| row[:case_id] }).to eq(["big", "small"])
    end
  end

  describe "score moves" do
    let(:comparison) do
      described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.0, min: 4)]),
          eval_result(case_id: "b", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.0, min: 4)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 5.0, min: 4)]),
          eval_result(case_id: "b", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.0, min: 4)])
        ] })
      )
    end

    it "compares the mean and breaks it down per case" do
      move = comparison.score_moves.first

      expect(move).to include(
        name: "clarity",
        baseline_mean: 4.0,
        candidate_mean: 4.5,
        delta: 0.5,
        regression: -0.5,
        gated: true,
        candidate_n: 2
      )
      expect(move[:per_case]).to eq([
        { case_id: "a", baseline_mean: 4.0, candidate_mean: 5.0, delta: 1.0 },
        { case_id: "b", baseline_mean: 4.0, candidate_mean: 4.0, delta: 0.0 }
      ])
    end

    it "omits a score whose mean did not move" do
      flat = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.0)])] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.0)])] })
      )

      expect(flat.score_moves).to be_empty
    end

    # A latency that halved and a score that halved are the same arithmetic, opposite news.
    it "treats a decrease as an improvement when lower is better" do
      latency = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "elapsed_ms", value: 900, higher_is_better: false)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "elapsed_ms", value: 600, higher_is_better: false)])
        ] })
      )

      move = latency.score_moves.first
      expect(move[:delta]).to eq(-300.0)
      expect(move[:regression]).to eq(-300.0)
      expect(latency.regressions).to be_empty
    end

    it "does not compare a score that only one run recorded" do
      one_sided = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.0)])] })
      )

      expect(one_sided.score_moves).to be_empty
    end

    # A candidate sampled down to a subset must not look improved because the cases it dropped
    # were the low-scoring ones. The only shared case here is unchanged, so there is no move.
    it "compares score means only across the cases both runs recorded" do
      subset = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 5.0, min: 4)]),
          eval_result(case_id: "b", expectations: { "e" => true }, scores: [score(name: "clarity", value: 1.0, min: 4)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 5.0, min: 4)])
        ] })
      )

      expect(subset.score_moves).to be_empty
      expect(subset.regressions.select { |row| row[:kind] == :score }).to be_empty
    end
  end

  describe "#not_comparable" do
    let(:comparison) do
      described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "shared", expectations: { "e" => true, "baseline only expectation" => true }),
          eval_result(case_id: "baseline-only-case", expectations: { "e" => true })
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "shared", expectations: { "e" => true }),
          eval_result(case_id: "candidate-only-case", expectations: { "e" => true })
        ] })
      )
    end

    # A silently omitted case looks exactly like agreement.
    it "reports cases present in only one run" do
      cases = comparison.not_comparable.select { |row| row[:expectation].nil? }

      expect(cases).to contain_exactly(
        hash_including(case_id: "baseline-only-case", present_in: "baseline only"),
        hash_including(case_id: "candidate-only-case", present_in: "candidate only")
      )
    end

    it "reports expectations present in only one run" do
      expect(comparison.not_comparable).to include(
        hash_including(case_id: "shared", expectation: "baseline only expectation", present_in: "baseline only")
      )
    end
  end

  describe "judge mismatch" do
    it "is detected when the two runs used different judges" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(expectations: { "e" => true })] }, judge: "anthropic_claude_5_sonnet"),
        candidate: payload({ "Set" => [eval_result(expectations: { "e" => true })] }, judge: "open_ai_gpt_5_4")
      )

      expect(comparison.judge_mismatch?).to be true
      expect(comparison.baseline_judge).to eq("anthropic_claude_5_sonnet")
      expect(comparison.candidate_judge).to eq("open_ai_gpt_5_4")
    end

    it "is not flagged when both runs used the same judge" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(expectations: { "e" => true })] })
      )

      expect(comparison.judge_mismatch?).to be false
    end

    # Each was graded by its own model under test. Read off the configured setting both sides say
    # "null", so the mismatch goes unnoticed in the one case the check exists for.
    it "is detected when neither run configured a judge and the models under test differ" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(expectations: { "e" => true })] }, model: "gpt_a", judge: "gpt_a")
          .tap { |p| p["configuration"]["evals_default_llm_judge_model_key"] = nil },
        candidate: payload({ "Set" => [eval_result(expectations: { "e" => true })] }, model: "gpt_b", judge: "gpt_b")
          .tap { |p| p["configuration"]["evals_default_llm_judge_model_key"] = nil }
      )

      expect(comparison.judge_mismatch?).to be true
      expect(comparison.baseline_judge).to eq("gpt_a")
      expect(comparison.candidate_judge).to eq("gpt_b")
    end

    it "is not flagged when neither run configured a judge and the model under test is the same" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(expectations: { "e" => true })] }, model: "gpt_a", judge: "gpt_a")
          .tap { |p| p["configuration"]["evals_default_llm_judge_model_key"] = nil },
        candidate: payload({ "Set" => [eval_result(expectations: { "e" => true })] }, model: "gpt_a", judge: "gpt_a")
          .tap { |p| p["configuration"]["evals_default_llm_judge_model_key"] = nil }
      )

      expect(comparison.judge_mismatch?).to be false
    end
  end

  describe "#regressed?" do
    let(:comparison) do
      described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 5.0, min: 4)]),
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 5.0, min: 4)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "clarity", value: 4.5, min: 4)]),
          eval_result(case_id: "a", expectations: { "e" => false }, scores: [score(name: "clarity", value: 4.5, min: 4)])
        ] })
      )
    end

    # Descriptions are not unique across eval sets, and the label is all a script reading the
    # JSON has to tell two rows apart by.
    it "qualifies a pass rate regression label with its eval set" do
      expect(comparison.regressions.map { |row| row[:label] }).to include("Set  produces expected output [a]")
    end

    # Magnitudes are fractions of the baseline, not absolute deltas: the rate halved (0.5), and
    # clarity's 0.5-point drop is a tenth of its 5.0 baseline. Being the same kind of number is
    # what lets one threshold apply to both.
    it "reports both the pass rate drop and the gated score drop, relative to baseline" do
      expect(comparison.regressions.map { |row| row.slice(:kind, :magnitude, :absolute) }).to contain_exactly(
        { kind: :pass_rate, magnitude: 0.5, absolute: 0.5 },
        { kind: :score, magnitude: 0.1, absolute: 0.5 }
      )
      expect(comparison.max_regression).to eq(0.5)
    end

    it "is true past the threshold and false at or below it" do
      expect(comparison.regressed?(0.25)).to be true
      expect(comparison.regressed?(0.5)).to be false
      expect(comparison.regressed?(nil)).to be false
    end

    # One expectation fixed while another broke leaves the eval rate flat, but it is still a
    # new failure and --fail-on-regression 0 must catch it, so the magnitude comes from the
    # expectation that dropped rather than from the (zero) rate delta.
    it "gives an expectation-only trade a positive magnitude" do
      traded = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => false, "second" => true })] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => true, "second" => false })] })
      )

      expect(traded.max_regression).to eq(1.0)
      expect(traded.regressed?(0)).to be true
    end

    # The same trade, but the eval came out ahead on its overall rate: "first" is fixed across
    # all three runs while "second" starts failing one of them. The improvement must not hide
    # the loss - the row reads better under FIXED, and it is still a regression to gate on.
    it "catches an expectation that dropped even when the eval's rate improved" do
      traded = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "first" => false, "second" => true }),
          eval_result(case_id: "a", expectations: { "first" => false, "second" => true }),
          eval_result(case_id: "a", expectations: { "first" => true, "second" => true })
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "first" => true, "second" => false }),
          eval_result(case_id: "a", expectations: { "first" => true, "second" => true }),
          eval_result(case_id: "a", expectations: { "first" => true, "second" => true })
        ] })
      )

      expect(traded.new_failures).to be_empty
      expect(traded.fixed.first).to include(baseline_rate: 0.3333, candidate_rate: 0.6667)
      expect(traded.fixed.first[:expectations]).to include(
        hash_including(description: "second", baseline_rate: 1.0, candidate_rate: 0.6667, delta: -0.3333)
      )

      expect(traded.regressions.map { |row| [row[:kind], row[:magnitude]] }).to contain_exactly([:pass_rate, 0.3333])
      expect(traded.regressed?(0)).to be true
      expect(traded.regressed?(0.5)).to be false
    end

    it "does not invent a regression for an eval that improved across the board" do
      improved = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => false, "second" => false })] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => true, "second" => true })] })
      )

      expect(improved.fixed.count).to eq(1)
      expect(improved.regressions).to be_empty
      expect(improved.regressed?(0)).to be false
    end

    # A score gated by a ceiling is gated, so a move away from that ceiling counts. As a
    # fraction of the baseline, 400ms -> 480ms is 0.2 rather than 80, so the same 0.25 that
    # catches a quarter of an eval's runs does not fire on 80 milliseconds.
    it "counts a max-gated score moving in the wrong direction, as a fraction of baseline" do
      latency = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true },
            scores: [score(name: "elapsed_ms", value: 400, max: 500, higher_is_better: false)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true },
            scores: [score(name: "elapsed_ms", value: 480, max: 500, higher_is_better: false)])
        ] })
      )

      expect(latency.score_moves.first).to include(gated: true, delta: 80.0, regression: 80.0)
      expect(latency.regressions.first).to include(kind: :score, magnitude: 0.2, absolute: 80.0)
      expect(latency.regressed?(0.1)).to be true
      expect(latency.regressed?(0.25)).to be false
    end

    # Two metrics on wildly different scales, each 10% worse, must land on the same magnitude -
    # that equivalence is the whole point of normalizing before applying the threshold.
    it "gives equal relative moves equal magnitudes regardless of scale" do
      scored = lambda do |clarity, latency|
        payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [
            score(name: "clarity", value: clarity, min: 1),
            score(name: "elapsed_ms", value: latency, max: 100_000, higher_is_better: false)
          ])
        ] })
      end

      comparison = described_class.new(baseline: scored.call(5.0, 1000), candidate: scored.call(4.5, 1100))

      expect(comparison.regressions.map { |row| [row[:label], row[:magnitude]] }).to contain_exactly(
        ["clarity", 0.1],
        ["elapsed_ms", 0.1]
      )
    end

    # A baseline of zero has no fraction to take, and 0 errors becoming 3 is exactly the kind of
    # regression that must not be quietly dropped for want of a denominator.
    it "treats a regression from a zero baseline as unbounded rather than absent" do
      errors = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true },
            scores: [score(name: "error_count", value: 0, max: 0, higher_is_better: false)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true },
            scores: [score(name: "error_count", value: 3, max: 0, higher_is_better: false)])
        ] })
      )

      expect(errors.regressions.first).to include(kind: :score, magnitude: nil, absolute: 3.0)
      expect(errors.unbounded_regressions.count).to eq(1)
      expect(errors.max_regression).to eq(0.0)
      expect(errors.regressed?(100)).to be true
      expect(errors.regressed?(nil)).to be false
      # Float::INFINITY would round-trip as invalid JSON, so the magnitude stays null.
      expect(JSON.generate(errors.to_h)).to include("\"magnitude\":null")
    end

    it "ignores an ungated score, however far it moved" do
      observational = described_class.new(
        baseline: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "summary_word_count", value: 400)])
        ] }),
        candidate: payload({ "Set" => [
          eval_result(case_id: "a", expectations: { "e" => true }, scores: [score(name: "summary_word_count", value: 100)])
        ] })
      )

      expect(observational.score_moves.first[:gated]).to be false
      expect(observational.regressions).to be_empty
      expect(observational.regressed?(0.25)).to be false
    end
  end

  describe "#to_h" do
    it "summarizes both sides" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => true })] }, model: "gpt_a", cost: 1.10),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "e" => false })] }, model: "gpt_b", cost: 1.64),
        baseline_label: "a.json",
        candidate_label: "b.json"
      )

      expect(comparison.to_h[:baseline]).to include(label: "a.json", model: "gpt_a", total_cost: 1.10, evals: 1, cases: 1, runs: 1)
      expect(comparison.to_h[:candidate]).to include(label: "b.json", model: "gpt_b", total_cost: 1.64)
    end

    it "works on results with no case ids at all" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(expectations: { "e" => false })] })
      )

      expect(comparison.new_failures.first).to include(case_id: nil, delta: -1.0)
      expect(comparison.to_h[:candidate][:cases]).to eq(0)
    end
  end
end
