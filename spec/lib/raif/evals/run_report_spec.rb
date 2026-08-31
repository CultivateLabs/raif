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
