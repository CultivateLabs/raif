# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ComparisonReport do
  def eval_result(case_id:, passed:, score_value:, errored: false)
    {
      "description" => "produces expected output",
      "eval_id" => "SummarizationEvalSet#produces-expected-output-9c1de4a70b2f",
      "eval_index" => 0,
      "case_id" => case_id,
      "passed" => passed && !errored,
      "expectation_results" => [{
        "description" => "is between 100 and 1000 words",
        "status" => errored ? "error" : (passed ? "passed" : "failed")
      }],
      "scores" => errored ? [] : [{ "name" => "clarity", "value" => score_value, "scale" => "1..5", "higher_is_better" => true, "min" => 4 }]
    }
  end

  def payload(results, model:, cost:, datasets: nil, judge_cost: nil, code: nil)
    configuration = {
      "default_llm_model_key" => model,
      "evals_default_llm_judge_model_key" => "anthropic_claude_5_sonnet",
      "judge_model_key" => "anthropic_claude_5_sonnet",
      "repeats" => 1
    }
    configuration["datasets"] = datasets unless datasets.nil?
    configuration["code"] = code unless code.nil?

    {
      "run_at" => "2026-08-04T18:02:16Z",
      "configuration" => configuration,
      "results" => { "SummarizationEvalSet" => results },
      "summary" => {
        "passed_evals" => results.count { |r| r["passed"] },
        "total_evals" => results.count,
        "passed_expectations" => results.count { |r| r["passed"] },
        "total_expectations" => results.count,
        "total_cost" => cost,
        "total_judge_cost" => judge_cost
      }.compact
    }
  end

  let(:comparison) do
    Raif::Evals::Comparison.new(
      baseline: payload(
        [eval_result(case_id: "press-release", passed: true, score_value: 5.0), eval_result(case_id: "gallium", passed: true, score_value: 4.0)],
        model: "gpt_a",
        cost: 1.10
      ),
      candidate: payload(
        [eval_result(case_id: "press-release", passed: false, score_value: 3.0), eval_result(case_id: "gallium", passed: true, score_value: 4.0)],
        model: "gpt_b",
        cost: 1.64
      ),
      baseline_label: "a.json",
      candidate_label: "b.json"
    )
  end

  let(:report) { described_class.new(comparison, threshold: 0.25, color: false) }

  describe "text" do
    subject(:text) { report.render("text") }

    it "reports both runs, the regression, and the verdict" do
      expect(text).to include("baseline   gpt_a   2026-08-04 18:02   1 evals x 1 repeats   2 cases   $1.10   a.json")
      expect(text).to include("candidate  gpt_b")
      expect(text).to include("anthropic_claude_5_sonnet (both runs)")
      expect(text).to include("NEW FAILURES (1)")
      expect(text).to include("press-release        1.00 -> 0.00")
      expect(text).to include("is between 100 and 1000 words")
      expect(text).to include("SCORE MOVES (1)")
      expect(text).to include("clarity  4.5 -> 3.5  -1.0  (-22.2%")
      expect(text).to include("evals passed          2/2 -> 1/2")
      expect(text).to include("total cost            $1.10 -> $1.64")
      # One, not two: the pass rate went 1.00 -> 0.00, but clarity's 1-point drop is 22% of a 4.5
      # baseline and sits under the 25% threshold. Compared absolutely it would have counted.
      #
      # And that one regression does not fail the run: one of two cases moved, which a sign test
      # cannot separate from noise. "nothing moved" and "something moved and we cannot tell" are
      # different news, so the verdict has to say which one it found.
      expect(text).to include("REGRESSION GATE (1)")
      expect(text).to include("1/1 cases worse, p=1.0")
      expect(text).to include(
        "1 regression beyond --fail-on-regression 0.25 (25% worse than baseline), none distinguishable from " \
        "run-to-run variation at a family-wise 0.05 over 1 candidate row"
      )
    end

    # The same report, with enough cases moving the same way for the gate to commit.
    it "reports an exit 1 verdict when the regression clears both bars" do
      cases = 8.times.map { |i| "case-#{i}" }
      wide = lambda do |model, passed, value|
        payload(cases.map { |id| eval_result(case_id: id, passed: passed, score_value: value) }, model: model, cost: 1.0)
      end

      rendered = described_class.new(
        Raif::Evals::Comparison.new(baseline: wide.call("gpt_a", true, 5.0), candidate: wide.call("gpt_b", false, 3.0)),
        threshold: 0.25,
        color: false
      ).render("text")

      expect(rendered).to include("8/8 cases worse, p=0.007813")
      expect(rendered).to include("regressions beyond --fail-on-regression 0.25 (25% worse than baseline)")
      expect(rendered).to include("at a family-wise 0.05 over 2 candidate rows (exit 1)")
    end

    # A score with no dataset case behind it has no matched unit to test, and the report has to
    # name the way out rather than leaving the reader with an unexplained refusal.
    it "explains a gate that cannot be answered at all" do
      no_cases = lambda do |model, value|
        payload([eval_result(case_id: nil, passed: true, score_value: value)], model: model, cost: 1.0)
      end

      rendered = described_class.new(
        Raif::Evals::Comparison.new(baseline: no_cases.call("gpt_a", 5.0), candidate: no_cases.call("gpt_b", 2.0)),
        threshold: 0.25,
        color: false
      ).render("text")

      expect(rendered).to include("none of them testable")
      expect(rendered).to include("--significance 1 to gate on effect size alone")
      expect(rendered).to include("(exit 2)")
    end

    it "says evidence was not required when the level is waived" do
      rendered = described_class.new(comparison, threshold: 0.25, color: false, alpha: 1).render("text")

      expect(rendered).to include("evidence not required (--significance 1)")
      expect(rendered).to include("(exit 1)")
    end

    it "omits sections with nothing in them" do
      expect(text).not_to include("FIXED")
      expect(text).not_to include("NOT COMPARABLE")
    end

    it "says so when no threshold was given" do
      expect(described_class.new(comparison, color: false).render("text")).to include("no regression threshold set")
    end

    # A one-case run at --repeat 1 has a single observation per side, and "sd 0.0 -> 0.0"
    # there would claim a spread was measured when nothing was.
    it "omits the standard deviation when neither side has more than one observation" do
      single = Raif::Evals::Comparison.new(
        baseline: payload([eval_result(case_id: "press-release", passed: true, score_value: 5.0)], model: "gpt_a", cost: 0.1),
        candidate: payload([eval_result(case_id: "press-release", passed: true, score_value: 3.0)], model: "gpt_b", cost: 0.1),
        baseline_label: "a.json",
        candidate_label: "b.json"
      )
      rendered = described_class.new(single, color: false).render("text")

      expect(rendered).to include("clarity  5.0 -> 3.0  -2.0  (-40.0%, n=1")
      expect(rendered).not_to include("sd")
    end

    it "truncates an expectation description too long for one line" do
      long = "The text does NOT set an analytic agenda for the reader: it does not tell the reader what questions to " \
        "investigate, nor propose that further structured analysis be performed"
      wordy = Raif::Evals::Comparison.new(
        baseline: payload([eval_result(case_id: "press-release", passed: true, score_value: 5.0).merge(
          "expectation_results" => [{ "description" => long, "status" => "passed" }]
        )], model: "gpt_a", cost: 0.1),
        candidate: payload([eval_result(case_id: "press-release", passed: false, score_value: 5.0).merge(
          "expectation_results" => [{ "description" => long, "status" => "failed" }]
        )], model: "gpt_b", cost: 0.1),
        baseline_label: "a.json",
        candidate_label: "b.json"
      )
      rendered = described_class.new(wordy, color: false).render("text")

      expect(rendered).to include("#{long[0, Raif::Evals::ConsoleLine::MAX_DESCRIPTION_LENGTH].rstrip}...")
      expect(rendered).not_to include(long)
    end

    it "flags a judge mismatch in the header" do
      mismatched = Raif::Evals::Comparison.new(
        baseline: comparison.baseline,
        candidate: comparison.candidate.merge(
          "configuration" => comparison.candidate["configuration"].merge("judge_model_key" => "other_judge")
        )
      )

      expect(described_class.new(mismatched, color: false).render("text")).to include("MISMATCHED")
    end
  end

  # An infrastructure error is not a quality result, and the report has to say which it is
  # looking at.
  describe "a run that errored" do
    let(:flaky) do
      Raif::Evals::Comparison.new(
        baseline: payload(
          [eval_result(case_id: "press-release", passed: true, score_value: 5.0),
           eval_result(case_id: "gallium", passed: true, score_value: 4.0)],
          model: "gpt_a",
          cost: 1.10
        ),
        candidate: payload(
          [eval_result(case_id: "press-release", passed: false, score_value: 3.0),
           eval_result(case_id: "gallium", passed: false, score_value: 0.0, errored: true)],
          model: "gpt_b",
          cost: 1.64
        )
      )
    end

    it "gives the error rate its own section in the text report" do
      text = described_class.new(flaky, threshold: 0.25, color: false).render("text")

      expect(text).to include("ERROR RATES (1)")
      expect(text).to include("0/2 -> 1/2 runs errored")
      expect(text).to include("gallium              candidate: all 1 run errored")
      expect(text).to include("evals errored")
    end

    # The gate cannot rule out that the run which errored was the one that would have changed the
    # answer, so the verdict says it declined rather than reporting a pass or a fail.
    it "declines the verdict rather than reporting one" do
      text = described_class.new(flaky, threshold: 0.25, color: false).render("text")

      expect(text).to include("gate declined: 50.0% of runs errored, above the 5% ceiling (exit 2)")
    end

    it "gates normally once the ceiling is waived" do
      text = described_class.new(flaky, threshold: 0.25, color: false, max_error_rate: 1).render("text")

      expect(text).not_to include("gate declined")
    end

    it "gives the error rate its own section in the HTML report" do
      html = described_class.new(flaky, threshold: 0.25, color: false).render("html")

      expect(html).to include("Error rates (1)")
      expect(html).to include("Evals errored")
      expect(html).to include("all 1 run errored")
    end
  end

  describe "a dataset that changed between the runs" do
    let(:edited) do
      Raif::Evals::Comparison.new(
        baseline: payload(
          [eval_result(case_id: "press-release", passed: true, score_value: 5.0)],
          model: "gpt_a",
          cost: 1.10,
          datasets: [{ "eval_set" => "SummarizationEvalSet", "name" => "documents", "cases" => 2, "digest" => "sha256:aaa" }],
          code: { "git_sha" => "abc123def456789", "dirty" => false }
        ),
        candidate: payload(
          [eval_result(case_id: "press-release", passed: false, score_value: 3.0)],
          model: "gpt_b",
          cost: 1.64,
          datasets: [{ "eval_set" => "SummarizationEvalSet", "name" => "documents", "cases" => 3, "digest" => "sha256:bbb" }],
          code: { "git_sha" => "def456abc123789", "dirty" => true }
        )
      )
    end

    it "warns in the text report, above the findings the reader is about to act on" do
      text = described_class.new(edited, threshold: 0.25, color: false).render("text")

      expect(text).to include("Warning: these two runs did not measure the same datasets:")
      expect(text).to include("documents (SummarizationEvalSet): 2 cases sha256:aaa -> 3 cases sha256:bbb")
      expect(text.index("did not measure the same datasets")).to be < text.index("NEW FAILURES")
    end

    it "reports each run's commit" do
      text = described_class.new(edited, color: false).render("text")

      expect(text).to include("code       abc123def456 -> def456abc123 (dirty)")
    end

    it "warns in the HTML report" do
      html = described_class.new(edited, threshold: 0.25, color: false).render("html")

      expect(html).to include("changed")
      expect(html).to include("2 cases sha256:aaa")
      expect(html).to include("abc123def456")
    end

    it "has nothing to warn about when both runs measured the same dataset" do
      expect(described_class.new(edited, color: false).dataset_warning).to be_present
      expect(described_class.new(comparison, color: false).dataset_warning).to be_nil
    end
  end

  describe "judge cost" do
    let(:split) do
      Raif::Evals::Comparison.new(
        baseline: payload([eval_result(case_id: "press-release", passed: true, score_value: 5.0)],
          model: "gpt_a", cost: 1.10, judge_cost: 0.20),
        candidate: payload([eval_result(case_id: "press-release", passed: false, score_value: 3.0)],
          model: "gpt_b", cost: 1.64, judge_cost: 0.24)
      )
    end

    it "splits the total cost row into the model under test and the judge" do
      text = described_class.new(split, color: false).render("text")

      expect(text).to include("total cost            $1.10 -> $1.64")
      expect(text).to include("model under test    $0.90 -> $1.40")
      expect(text).to include("judge               $0.20 -> $0.24")
    end

    it "splits the total cost row in the HTML report" do
      html = described_class.new(split, color: false).render("html")

      expect(html).to include("Model under test")
      expect(html).to include("$0.90")
    end

    # Unknown rather than zero for a run recorded before the split existed: printing $0.00 would
    # read as a run that used no judge.
    it "prints a dash for a run that did not record judge spend" do
      partial = Raif::Evals::Comparison.new(
        baseline: payload([eval_result(case_id: "press-release", passed: true, score_value: 5.0)], model: "gpt_a", cost: 1.10),
        candidate: payload([eval_result(case_id: "press-release", passed: false, score_value: 3.0)],
          model: "gpt_b", cost: 1.64, judge_cost: 0.24)
      )

      expect(described_class.new(partial, color: false).render("text")).to include("judge               - -> $0.24")
    end

    it "leaves the total cost row alone when neither run recorded judge spend" do
      expect(described_class.new(comparison, color: false).render("text")).not_to include("model under test")
    end

    # A run that used no judge records a judge cost of zero. Splitting the row there would say the
    # same thing twice.
    it "leaves the total cost row alone when both runs recorded no judge spend at all" do
      judgeless = Raif::Evals::Comparison.new(
        baseline: payload([eval_result(case_id: "press-release", passed: true, score_value: 5.0)],
          model: "gpt_a", cost: 1.10, judge_cost: 0.0),
        candidate: payload([eval_result(case_id: "press-release", passed: false, score_value: 3.0)],
          model: "gpt_b", cost: 1.64, judge_cost: 0.0)
      )

      expect(described_class.new(judgeless, color: false).render("text")).not_to include("model under test")
    end
  end

  describe "json" do
    it "renders the comparison structure" do
      parsed = JSON.parse(report.render("json"))

      expect(parsed["new_failures"].first["case_id"]).to eq("press-release")
      expect(parsed["score_moves"].first["name"]).to eq("clarity")
    end
  end

  describe "html" do
    subject(:html) { report.render("html") }

    it "renders a self-contained document with no external asset references" do
      expect(html).to start_with("<!DOCTYPE html>")
      expect(html).to include("</html>")
      expect(html).not_to match(/<(script|link)\b/)
      expect(html).not_to match(/https?:\/\//)
    end

    it "includes the findings" do
      expect(html).to include("New failures (1)")
      expect(html).to include("press-release")
      expect(html).to include("Score moves (1)")
      expect(html).to include("clarity")
      expect(html).to include("none distinguishable from run-to-run variation")
      expect(html).to include("-22.2%")
    end

    it "escapes content that came out of the results file" do
      injected = Raif::Evals::Comparison.new(
        baseline: comparison.baseline,
        candidate: comparison.candidate.merge(
          "configuration" => comparison.candidate["configuration"].merge("default_llm_model_key" => "<script>alert(1)</script>")
        )
      )

      rendered = described_class.new(injected, color: false).render("html")
      expect(rendered).to include("&lt;script&gt;")
      expect(rendered).not_to include("<script>")
    end
  end
end
