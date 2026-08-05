# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ComparisonReport do
  def eval_result(case_id:, passed:, score_value:)
    {
      "description" => "produces expected output",
      "eval_index" => 0,
      "case_id" => case_id,
      "passed" => passed,
      "expectation_results" => [{ "description" => "is between 100 and 1000 words", "status" => passed ? "passed" : "failed" }],
      "scores" => [{ "name" => "clarity", "value" => score_value, "scale" => "1..5", "higher_is_better" => true, "min" => 4 }]
    }
  end

  def payload(results, model:, cost:)
    {
      "run_at" => "2026-08-04T18:02:16Z",
      "configuration" => {
        "default_llm_model_key" => model,
        "evals_default_llm_judge_model_key" => "anthropic_claude_5_sonnet",
        "repeats" => 1
      },
      "results" => { "SummarizationEvalSet" => results },
      "summary" => {
        "passed_evals" => results.count { |r| r["passed"] },
        "total_evals" => results.count,
        "passed_expectations" => results.count { |r| r["passed"] },
        "total_expectations" => results.count,
        "total_cost" => cost
      }
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
      expect(text).to include("clarity  4.5 -> 3.5  -1.0")
      expect(text).to include("evals passed          2/2 -> 1/2")
      expect(text).to include("total cost            $1.10 -> $1.64")
      expect(text).to include("2 regressions beyond --fail-on-regression 0.25 (exit 1)")
    end

    it "omits sections with nothing in them" do
      expect(text).not_to include("FIXED")
      expect(text).not_to include("NOT COMPARABLE")
    end

    it "says so when no threshold was given" do
      expect(described_class.new(comparison, color: false).render("text")).to include("no regression threshold set")
    end

    it "flags a judge mismatch in the header" do
      mismatched = Raif::Evals::Comparison.new(
        baseline: comparison.baseline,
        candidate: comparison.candidate.merge(
          "configuration" => comparison.candidate["configuration"].merge("evals_default_llm_judge_model_key" => "other_judge")
        )
      )

      expect(described_class.new(mismatched, color: false).render("text")).to include("MISMATCHED")
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
      expect(html).to include("regressions beyond --fail-on-regression 0.25")
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
