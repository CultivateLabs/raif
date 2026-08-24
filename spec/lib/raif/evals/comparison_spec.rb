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
      "passed" => expectations.values.all?(true),
      "expectation_results" => expectations.map do |expectation_description, status|
        { "description" => expectation_description, "status" => expectation_status(status) }
      end,
      "scores" => scores
    }
  end

  # true/false is a passed/failed expectation; :error is one that raised. Written the way an
  # older results file writes it - a status and no "errored" key - since that is what the
  # comparison has to keep working on.
  def expectation_status(value)
    case value
    when true then "passed"
    when false then "failed"
    else value.to_s
    end
  end

  def score(name:, value:, min: nil, max: nil, higher_is_better: true)
    { "name" => name, "value" => value, "higher_is_better" => higher_is_better, "min" => min, "max" => max }.compact
  end

  # datasets and judge_cost are absent unless a spec asks for them, which is how a results file
  # written before either was recorded reads.
  def payload(results, judge: "anthropic_claude_5_sonnet", model: "gpt_a", cost: 1.10, datasets: nil, judge_cost: nil, code: nil)
    configuration = {
      "default_llm_model_key" => model,
      "evals_default_llm_judge_model_key" => judge,
      "judge_model_key" => judge,
      "repeats" => 2
    }
    configuration["datasets"] = datasets unless datasets.nil?
    configuration["code"] = code unless code.nil?

    {
      "run_at" => "2026-08-04T18:02:16Z",
      "configuration" => configuration,
      "results" => results,
      "summary" => {
        "passed_evals" => results.values.flatten.count { |r| r["passed"] },
        "total_evals" => results.values.flatten.count,
        "passed_expectations" => results.values.flatten.sum { |r| r["expectation_results"].count { |e| e["status"] == "passed" } },
        "total_expectations" => results.values.flatten.sum { |r| r["expectation_results"].count },
        "total_cost" => cost,
        "total_judge_cost" => judge_cost
      }.compact
    }
  end

  def dataset_fingerprint(name: "topics", eval_set: "Set", cases: 3, digest: "sha256:aaa")
    { "eval_set" => eval_set, "name" => name, "cases" => cases, "digest" => digest }
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

  describe "dataset provenance" do
    def one_result
      { "Set" => [eval_result(case_id: "a", expectations: { "e" => true })] }
    end

    it "is not flagged when both runs measured the same dataset" do
      comparison = described_class.new(
        baseline: payload(one_result, datasets: [dataset_fingerprint]),
        candidate: payload(one_result, datasets: [dataset_fingerprint])
      )

      expect(comparison.dataset_provenance?).to be true
      expect(comparison.dataset_mismatch?).to be false
      expect(comparison.dataset_differences).to be_empty
    end

    # The failure this exists for: the case ids still match, so without the fingerprint the edit is
    # attributed to the model.
    it "is flagged when a case was edited between the two runs" do
      comparison = described_class.new(
        baseline: payload(one_result, datasets: [dataset_fingerprint(digest: "sha256:aaa")]),
        candidate: payload(one_result, datasets: [dataset_fingerprint(digest: "sha256:bbb")])
      )

      expect(comparison.dataset_mismatch?).to be true
      expect(comparison.dataset_differences).to eq([{
        name: "topics",
        eval_set: "Set",
        baseline: "3 cases sha256:aaa",
        candidate: "3 cases sha256:bbb"
      }])
    end

    it "is flagged when the dataset grew" do
      comparison = described_class.new(
        baseline: payload(one_result, datasets: [dataset_fingerprint(cases: 3, digest: "sha256:aaa")]),
        candidate: payload(one_result, datasets: [dataset_fingerprint(cases: 4, digest: "sha256:bbb")])
      )

      expect(comparison.dataset_differences.first).to include(baseline: "3 cases sha256:aaa", candidate: "4 cases sha256:bbb")
    end

    it "is flagged when a dataset only one run has" do
      comparison = described_class.new(
        baseline: payload(one_result, datasets: []),
        candidate: payload(one_result, datasets: [dataset_fingerprint])
      )

      expect(comparison.dataset_differences.first).to include(name: "topics", baseline: "not run", candidate: "3 cases sha256:aaa")
    end

    # A run recorded before fingerprints existed has no datasets key. Reporting a match from that
    # would be a claim the file cannot support.
    it "says nothing when either run recorded no dataset provenance" do
      comparison = described_class.new(
        baseline: payload(one_result),
        candidate: payload(one_result, datasets: [dataset_fingerprint])
      )

      expect(comparison.dataset_provenance?).to be false
      expect(comparison.dataset_mismatch?).to be false
    end

    it "exposes each run's code provenance" do
      comparison = described_class.new(
        baseline: payload(one_result, code: { "git_sha" => "abc123", "dirty" => false }),
        candidate: payload(one_result, code: { "git_sha" => "def456", "dirty" => true })
      )

      expect(comparison.baseline_code).to eq({ "git_sha" => "abc123", "dirty" => false })
      expect(comparison.candidate_code).to eq({ "git_sha" => "def456", "dirty" => true })
    end
  end

  describe "judge cost" do
    def one_result
      { "Set" => [eval_result(expectations: { "e" => true })] }
    end

    # The judge is held fixed across a comparison, so its share of the bill is not part of what
    # separates the two models under test.
    it "splits each side's total into subject and judge spend" do
      comparison = described_class.new(
        baseline: payload(one_result, cost: 1.10, judge_cost: 0.20),
        candidate: payload(one_result, cost: 1.64, judge_cost: 0.24)
      )

      expect(comparison.to_h[:baseline]).to include(total_cost: 1.10, judge_cost: 0.20, subject_cost: 0.90)
      expect(comparison.to_h[:candidate]).to include(total_cost: 1.64, judge_cost: 0.24, subject_cost: 1.40)
    end

    # Unknown rather than all-subject: a run written before the split existed did not record it.
    it "leaves the split nil for a run that did not record judge spend" do
      comparison = described_class.new(
        baseline: payload(one_result, cost: 1.10),
        candidate: payload(one_result, cost: 1.64, judge_cost: 0.24)
      )

      expect(comparison.to_h[:baseline]).to include(judge_cost: nil, subject_cost: nil)
      expect(comparison.to_h[:candidate]).to include(judge_cost: 0.24, subject_cost: 1.40)
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
      expect(comparison.regressions.map { |row| row[:label] }).to include("Set  produces expected output")
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

    # alpha: 1 isolates the size bar from the evidence bar. These fixtures are one case at two
    # repeats, which no test can separate from noise - that is what "the evidence bar" describes,
    # and it has its own section below.
    it "is true past the threshold and false at or below it" do
      expect(comparison.regressed?(0.25, alpha: 1)).to be true
      expect(comparison.regressed?(0.5, alpha: 1)).to be false
      expect(comparison.regressed?(nil, alpha: 1)).to be false
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
      expect(traded.regressed?(0, alpha: 1)).to be true
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
      expect(traded.regressed?(0, alpha: 1)).to be true
      expect(traded.regressed?(0.5, alpha: 1)).to be false
    end

    it "does not invent a regression for an eval that improved across the board" do
      improved = described_class.new(
        baseline: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => false, "second" => false })] }),
        candidate: payload({ "Set" => [eval_result(case_id: "a", expectations: { "first" => true, "second" => true })] })
      )

      expect(improved.fixed.count).to eq(1)
      expect(improved.regressions).to be_empty
      expect(improved.regressed?(0, alpha: 1)).to be false
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
      expect(latency.regressed?(0.1, alpha: 1)).to be true
      expect(latency.regressed?(0.25, alpha: 1)).to be false
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
      expect(errors.regressed?(100, alpha: 1)).to be true
      expect(errors.regressed?(nil, alpha: 1)).to be false
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
      expect(observational.regressed?(0.25, alpha: 1)).to be false
    end
  end

  # The other half of the gate: a move has to be big enough (above) AND consistent enough to tell
  # apart from run-to-run variation. Point estimates alone fire on noise until someone disables the
  # gate, which is worse than having no gate.
  describe "regression evidence" do
    # One eval, `count` dataset cases, each passing on the baseline and failing on the candidate.
    def wide(count, scores: false, passed:, value: 5.0)
      results = count.times.map do |i|
        eval_result(
          case_id: "case-#{i}",
          expectations: { "e" => passed },
          scores: scores ? [score(name: "clarity", value: value, min: 4)] : []
        )
      end

      payload({ "Set" => results })
    end

    it "fires when enough matched cases move the same way" do
      comparison = described_class.new(baseline: wide(8, passed: true), candidate: wide(8, passed: false))
      row = comparison.regressions.first

      expect(row).to include(kind: :pass_rate, evidence: :paired_cases, pairs: 8, worsened: 8, improved: 0)
      expect(row[:p_value]).to be_within(0.000001).of(0.007813)
      expect(comparison.regressed?(0.25)).to be true
    end

    # Five cases all worse is p=0.0625 - short of 0.05 however total the failure looks. Five
    # matched pairs genuinely cannot get below that, which is a property of the sample size rather
    # than a choice this code makes.
    it "does not fire when too few cases moved to reach the level" do
      comparison = described_class.new(baseline: wide(5, passed: true), candidate: wide(5, passed: false))

      expect(comparison.regressions.first[:p_value]).to be_within(0.000001).of(0.0625)
      expect(comparison.regressed?(0.25)).to be false
      # Still reported, and still over the size threshold - it is the verdict that withholds, not
      # the report.
      expect(comparison.candidate_regressions(0.25).count).to eq(1)
      expect(comparison.insufficient_evidence?(0.25)).to be false
    end

    # Six cases is p=0.03125: under 0.05 on its own, over 0.05/2 once a second candidate row is
    # tested alongside it. Without the correction, the gate fails if ANY of N rows clears 0.05,
    # which for a 20-row suite is a false failure in one run out of three.
    it "divides the level by the number of rows it tests" do
      one_row = described_class.new(baseline: wide(6, passed: true), candidate: wide(6, passed: false))
      two_rows = described_class.new(
        baseline: wide(6, passed: true, scores: true, value: 5.0),
        candidate: wide(6, passed: false, scores: true, value: 3.0)
      )

      expect(one_row.candidate_regressions(0.25).count).to eq(1)
      expect(one_row.regressed?(0.25)).to be true

      expect(two_rows.candidate_regressions(0.25).count).to eq(2)
      expect(two_rows.regressions.map { |row| row[:p_value] }).to all(be_within(0.000001).of(0.03125))
      expect(two_rows.regressed?(0.25)).to be false
      # The same data does fire once the level is not split.
      expect(two_rows.regressed?(0.25, alpha: 0.1)).to be true
    end

    # An eval with no dataset has no matched unit, so its pass rate goes to an exact test on the
    # repeat counts instead. At one repeat a side that test returns 1.0, which is the correct
    # answer to "one draw against one draw".
    it "falls back to an exact test on repeats when there are no cases" do
      comparison = described_class.new(
        baseline: payload({ "Set" => 6.times.map { eval_result(expectations: { "e" => true }) } }),
        candidate: payload({ "Set" => 6.times.map { eval_result(expectations: { "e" => false }) } })
      )
      row = comparison.regressions.first

      expect(row).to include(kind: :pass_rate, evidence: :repeats, pairs: 0)
      expect(row[:p_value]).to be_within(0.000001).of(0.002165)
      expect(comparison.regressed?(0.25)).to be true
    end

    it "cannot reach a verdict from a single repeat on each side" do
      comparison = described_class.new(
        baseline: payload({ "Set" => [eval_result(expectations: { "e" => true })] }),
        candidate: payload({ "Set" => [eval_result(expectations: { "e" => false })] })
      )

      expect(comparison.regressions.first[:p_value]).to eq(1.0)
      expect(comparison.regressed?(0.25)).to be false
    end

    # A continuous score has no exact two-sample test at these counts, so rather than invent one,
    # the row is marked untestable - and the gate says so instead of exiting 0 on it.
    it "marks a score with no matched cases unverifiable rather than passing it" do
      scored = lambda do |value|
        payload({ "Set" => [eval_result(expectations: { "e" => true }, scores: [score(name: "clarity", value: value, min: 1)])] })
      end

      comparison = described_class.new(baseline: scored.call(5.0), candidate: scored.call(2.0))
      row = comparison.regressions.find { |r| r[:kind] == :score }

      expect(row).to include(evidence: :none, p_value: nil)
      expect(comparison.unverifiable_regressions(0.25)).to contain_exactly(row)
      expect(comparison.insufficient_evidence?(0.25)).to be true
      expect(comparison.regressed?(0.25)).to be false
      # Waiving the requirement is how a caller who accepts the risk gates on size alone.
      expect(comparison.regressed?(0.25, alpha: 1)).to be true
      expect(comparison.insufficient_evidence?(0.25, alpha: 1)).to be false
    end

    # A score regresses upward when it is max-gated, so the direction each case moved has to be
    # read against higher_is_better rather than off the sign of the delta.
    it "reads case direction against higher_is_better for a max-gated score" do
      latency = lambda do |value|
        payload({ "Set" => 8.times.map do |i|
          eval_result(case_id: "case-#{i}", expectations: { "e" => true },
            scores: [score(name: "elapsed_ms", value: value, max: 500, higher_is_better: false)])
        end })
      end

      comparison = described_class.new(baseline: latency.call(400), candidate: latency.call(480))
      row = comparison.regressions.find { |r| r[:kind] == :score }

      expect(row).to include(evidence: :paired_cases, worsened: 8, improved: 0)
      expect(comparison.regressed?(0.1)).to be true
    end

    # Nothing cleared the size bar, so there is nothing to be uncertain about.
    it "is not insufficient evidence when nothing regressed" do
      steady = described_class.new(baseline: wide(8, passed: true), candidate: wide(8, passed: true))

      expect(steady.insufficient_evidence?(0.25)).to be false
      expect(steady.regressed?(0.25)).to be false
    end

    it "never fails without a threshold, however consistent the move" do
      comparison = described_class.new(baseline: wide(20, passed: true), candidate: wide(20, passed: false))

      expect(comparison.regressed?(nil)).to be false
      expect(comparison.insufficient_evidence?(nil)).to be false
      expect(comparison.candidate_regressions(nil)).to be_empty
    end
  end

  # An error is a missing measurement, not a bad one. Folding the two together makes a provider
  # incident on one side read as a pass-rate regression on that side.
  describe "runs that errored" do
    def errored_payload(statuses, **options)
      payload({ "Set" => statuses.map.with_index do |status, index|
        eval_result(eval_id: "Set#e-abc123", case_id: "case-#{index}", expectations: { "works" => status })
      end }, **options)
    end

    # The denominator itself: one case, two repeats, one of which raised. The surviving repeat
    # passed, so the case's rate is 1.0 - not the 0.5 that scoring the error as a miss gives.
    it "divides by the runs that produced a measurement, not by every run" do
      repeats = lambda do |*statuses|
        payload({ "Set" => statuses.map do |status|
          eval_result(eval_id: "Set#e-abc123", case_id: "only", expectations: { "works" => status })
        end })
      end

      comparison = described_class.new(baseline: repeats.call(true, true), candidate: repeats.call(true, :error))

      expect(comparison.new_failures).to be_empty
      expect(comparison.not_comparable).to be_empty
      expect(comparison.error_moves.first).to include(candidate_errored: 1, candidate_runs: 2, delta: 0.5)
    end

    it "keeps an errored run out of the pass rate rather than counting it as a failure" do
      comparison = described_class.new(
        baseline: errored_payload([true, true]),
        candidate: errored_payload([true, :error])
      )

      # The one case that produced a measurement passed on both sides, so nothing regressed. With
      # the error counted as a miss the candidate would read 0.5 against a baseline of 1.0.
      expect(comparison.new_failures).to be_empty
      expect(comparison.regressions).to be_empty
    end

    # Not a 100% regression: the case measured nothing, which is the same problem as a case only
    # one side ran.
    it "reports a case that errored on every run as not comparable" do
      comparison = described_class.new(
        baseline: errored_payload([true, true]),
        candidate: errored_payload([true, :error, :error])
      )

      row = comparison.not_comparable.find { |r| r[:case_id] == "case-1" }

      expect(row).to include(present_in: "both", reason: "candidate: all 1 run errored")
      expect(comparison.new_failures).to be_empty
      expect(comparison.regressions).to be_empty
    end

    it "reports the error rate move on its own" do
      comparison = described_class.new(
        baseline: errored_payload([true, true, true, true]),
        candidate: errored_payload([true, :error, true, true])
      )

      expect(comparison.error_moves).to contain_exactly(
        include(eval_id: "Set#e-abc123", baseline_errored: 0, candidate_errored: 1, candidate_runs: 4,
          baseline_rate: 0.0, candidate_rate: 0.25, delta: 0.25)
      )
    end

    it "says nothing about error rates when neither side errored" do
      comparison = described_class.new(baseline: errored_payload([true, false]), candidate: errored_payload([true, true]))

      expect(comparison.error_moves).to be_empty
      expect(comparison.baseline_error_rate).to eq(0.0)
      expect(comparison.error_rate_unreliable?).to be false
    end

    it "reports a side's overall error rate in its summary" do
      comparison = described_class.new(
        baseline: errored_payload([true, true, true, true]),
        candidate: errored_payload([true, :error, true, true])
      )

      expect(comparison.to_h[:candidate]).to include(errored_evals: 1, error_rate: 0.25)
      expect(comparison.to_h[:baseline]).to include(errored_evals: 0, error_rate: 0.0)
    end

    describe "#error_rate_unreliable?" do
      # What the gate refuses on: the surviving runs may not be a fair sample of the ones that
      # errored, and past this rate that bias can decide a close comparison on its own.
      it "is true when either side lost more than the ceiling to errors" do
        comparison = described_class.new(
          baseline: errored_payload([true, true, true, true]),
          candidate: errored_payload([true, :error, true, true])
        )

        expect(comparison.error_rate_unreliable?).to be true
      end

      it "tolerates a rate at or under the ceiling" do
        comparison = described_class.new(
          baseline: errored_payload(Array.new(20, true)),
          candidate: errored_payload([:error] + Array.new(19, true))
        )

        expect(comparison.candidate_error_rate).to eq(0.05)
        expect(comparison.error_rate_unreliable?).to be false
      end

      it "can be waived entirely" do
        comparison = described_class.new(
          baseline: errored_payload([true, true]),
          candidate: errored_payload([:error, :error])
        )

        expect(comparison.error_rate_unreliable?(max_error_rate: 1)).to be false
      end
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
