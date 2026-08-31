# frozen_string_literal: true

require "rails_helper"
require "raif/evals/run_report"

RSpec.describe Raif::Evals::RunReport do
  let(:payload) { cli_results_payload(model: "gpt_a", passed: false, score_value: 3.0) }

  it "renders the run's header, totals and failure detail" do
    html = described_class.new(payload, label: "run.json").html

    expect(html).to include("Raif eval run")
    expect(html).to include("gpt_a")
    expect(html).to include("judge_model")
    expect(html).to include("run.json")
    expect(html).to include("Failures (1)")
    expect(html).to include("is under 1000 words")
  end

  it "says so when nothing failed" do
    html = described_class.new(cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0)).html

    expect(html).to include("Failures (0)")
    expect(html).to include("None. Every expectation passed.")
  end

  describe "#failures" do
    it "collects every expectation that did not pass, with the context to find it again" do
      report = described_class.new(payload)

      expect(report.failures.length).to eq(1)
      expect(report.failures.first).to include(
        "eval_set" => "SummarizationEvalSet",
        "case_id" => "press-release"
      )
    end

    # A gated score records both a failed expectation and a score carrying passed: false. Counting
    # both would report one failure as two.
    it "counts a gated score's failure once, through its expectation" do
      report = described_class.new(payload)

      expect(report.failures.map { |row| row["expectation"]["description"] }).to eq(["is under 1000 words"])
    end

    it "includes an errored expectation, which is a missing measurement rather than a passing one" do
      errored = cli_results_payload(
        model: "gpt_a", passed: true, score_value: 5.0,
        case_ids: ["press-release"], errored_case_ids: ["press-release"]
      )

      expect(described_class.new(errored).failures.length).to eq(1)
    end
  end

  # The page carries expectation metadata and judge reasoning, which is model output.
  it "escapes model-supplied text rather than rendering it as markup" do
    payload["results"]["SummarizationEvalSet"].first["expectation_results"].first["metadata"] = {
      "response" => "<script>alert(1)</script>"
    }

    html = described_class.new(payload).html

    expect(html).not_to include("<script>alert(1)</script>")
    expect(html).to include("&lt;script&gt;")
  end

  # Raif::Evals::Run holds symbol keys in memory and writes string keys to the file. Both render.
  it "accepts a symbol-keyed payload" do
    symbolized = JSON.parse(JSON.generate(payload), symbolize_names: true)

    expect(described_class.new(symbolized).html).to include("gpt_a")
  end

  # Raif::Evals::Run writes pass_rate: null when every run of an eval or a case errored. Nothing
  # was measured, and 0.00 would claim it all failed.
  describe "an eval whose runs all errored" do
    let(:payload) do
      base = cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0,
        case_ids: ["press-release", "memo"], errored_case_ids: ["memo"])

      base["summary"]["eval_pass_rates"] = [{
        "eval_set" => "SummarizationEvalSet",
        "description" => "produces expected output",
        "runs" => 2,
        "errored" => 1,
        "passed" => 1,
        "pass_rate" => 1.0,
        "per_case" => [
          { "case_id" => "press-release", "runs" => 1, "errored" => 0, "passed" => 1, "pass_rate" => 1.0 },
          { "case_id" => "memo", "runs" => 1, "errored" => 1, "passed" => 0, "pass_rate" => nil }
        ]
      }]

      base
    end

    it "renders an unknown rate as - rather than 0.00" do
      expect(described_class.new(payload).format_rate(nil)).to eq("-")
      expect(described_class.new(payload).rate_class(nil)).to eq("warn")
    end

    it "keeps a case that measured nothing out of the weakest cases" do
      report = described_class.new(payload)
      row = report.pass_rate_rows.first

      expect(report.failing_cases(row)).to be_empty
      expect(report.errored_cases(row).map { |c| c["case_id"] }).to eq(["memo"])
    end

    # The rate is passed out of what was measured, so the fraction beside it has to be too.
    it "leaves errored runs out of the passed fraction" do
      report = described_class.new(payload)

      expect(report.measured(report.pass_rate_rows.first)).to eq(1)
      expect(report.html).to include("1/1")
      expect(report.html).to include("(1 errored)")
    end

    # An eval can pass, fail, or raise. A red FAIL on a provider timeout reads as a quality drop.
    it "labels an errored execution ERROR rather than FAIL" do
      html = described_class.new(payload).html

      expect(described_class.new(payload).result_status({ "errored" => true, "passed" => false })).to eq(["ERROR", "warn"])
      expect(html).to include("ERROR")
      expect(html).not_to include(">FAIL<")
    end
  end

  # A max: gate is the supported form for a lower-is-better metric, and a score can carry both
  # bounds. Printing "min" unconditionally omits the bound that decided passed.
  describe "#gate_description" do
    it "names whichever bounds the score carries" do
      report = described_class.new(payload)

      expect(report.gate_description({ "min" => 4 })).to eq(">= 4")
      expect(report.gate_description({ "max" => 2.5 })).to eq("<= 2.5")
      expect(report.gate_description({ "min" => 1, "max" => 5 })).to eq(">= 1 and <= 5")
    end

    it "renders the gate a max-only score was measured against" do
      payload["results"]["SummarizationEvalSet"].first["scores"] = [
        { "name" => "latency", "value" => 4.0, "higher_is_better" => false, "max" => 2.5, "passed" => false }
      ]

      expect(described_class.new(payload).html).to include("&lt;= 2.5")
    end
  end

  describe "#capture_mode" do
    it "reports the mode the run recorded" do
      payload["configuration"]["capture_model_completions"] = "full"

      expect(described_class.new(payload).capture_mode).to eq("full")
      expect(described_class.new(payload).html).to include("Captured in full")
    end

    # A results file written before the setting existed records nothing, which is not the same as
    # recording that nothing was captured.
    it "falls back to none when the run recorded no mode" do
      expect(described_class.new(payload).capture_mode).to eq("none")
    end
  end

  it "refuses a format it cannot render" do
    expect { described_class.new(payload).render("pdf") }.to raise_error(ArgumentError, /Unsupported format: pdf/)
  end
end
