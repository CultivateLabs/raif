# frozen_string_literal: true

require "rails_helper"
require "raif/cli"

# Driven through the real executable rather than by calling the command object, because the
# command's contract includes what it loads: it reads two JSON files and does arithmetic,
# and is required to do so without booting Rails.
RSpec.describe Raif::CLI::EvalsCompare do
  around do |example|
    Dir.mktmpdir("raif-cli") do |dir|
      @dir = dir
      example.run
    end
  end

  attr_reader :dir

  let(:baseline) { write_payload(dir, "a.json", cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0)) }
  let(:candidate) { write_payload(dir, "b.json", cli_results_payload(model: "gpt_b", passed: false, score_value: 3.0)) }

  it "diffs two runs and exits zero when no threshold was given" do
    result = run_raif_cli("evals:compare", baseline, candidate)

    expect(result.exit_code).to eq(0)
    expect(result.stdout).to include("baseline   gpt_a")
    expect(result.stdout).to include("candidate  gpt_b")
    expect(result.stdout).to include("NEW FAILURES (1)")
    expect(result.stdout).to include("clarity  5.0 -> 3.0  -2.0")
    expect(result.stdout).to include("no regression threshold set")
  end

  it "exits 1 when a regression exceeds --fail-on-regression" do
    result = run_raif_cli("evals:compare", baseline, candidate, "--fail-on-regression", "0.25")

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("--fail-on-regression 0.25")
  end

  it "exits 0 when the regression is inside the threshold" do
    steady = write_payload(dir, "steady.json", cli_results_payload(model: "gpt_b", passed: true, score_value: 5.0))
    result = run_raif_cli("evals:compare", baseline, steady, "--fail-on-regression", "0.25")

    expect(result.exit_code).to eq(0)
  end

  describe "judge mismatch" do
    let(:other_judge) do
      write_payload(dir, "other_judge.json", cli_results_payload(model: "gpt_b", passed: false, score_value: 3.0, judge: "a_different_judge"))
    end

    it "refuses the comparison and exits 2" do
      result = run_raif_cli("evals:compare", baseline, other_judge)

      expect(result.exit_code).to eq(2)
      expect(result.stdout).to include("Refusing to compare runs judged by different models")
      expect(result.stdout).to include("a_different_judge")
    end

    it "compares anyway under --allow-judge-mismatch" do
      result = run_raif_cli("evals:compare", baseline, other_judge, "--allow-judge-mismatch")

      expect(result.exit_code).to eq(0)
      expect(result.stdout).to include("MISMATCHED")
    end
  end

  describe "formats" do
    it "emits parseable JSON under --format json" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--format", "json")
      parsed = JSON.parse(result.stdout)

      expect(parsed["score_moves"].first["name"]).to eq("clarity")
      expect(parsed["new_failures"].count).to eq(1)
    end

    it "writes a self-contained file under --format html" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--format", "html")
      written = File.join(dir, "eval_comparison_a_vs_b.html")

      expect(result.stdout).to include("Comparison report written to: #{written}")
      expect(File.read(written)).to include("<title>Raif eval comparison</title>")
    end

    it "rejects an unknown format with usage rather than a backtrace" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--format", "yaml")

      expect(result.exit_code).to eq(1)
      expect(result.output).to include("invalid argument: --format yaml")
      expect(result.output).to include("Usage: raif evals:compare")
      expect(result.output).not_to include("OptionParser::InvalidArgument")
    end

    it "rejects an unknown switch with usage rather than a backtrace" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--nope")

      expect(result.exit_code).to eq(1)
      expect(result.output).to include("invalid option: --nope")
      expect(result.output).to include("Usage: raif evals:compare")
      expect(result.output).not_to include("OptionParser")
    end
  end

  describe "bad input" do
    it "reports a missing file" do
      result = run_raif_cli("evals:compare", baseline, File.join(dir, "nope.json"))

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("File not found")
    end

    it "reports a file that is not JSON" do
      broken = File.join(dir, "broken.json")
      File.write(broken, "{not json")
      result = run_raif_cli("evals:compare", baseline, broken)

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("is not valid JSON")
    end

    it "prints usage when a path is missing" do
      result = run_raif_cli("evals:compare", baseline)

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("Usage: raif evals:compare")
    end

    # Valid JSON of the wrong shape compares cleanly and reports no regressions - a green exit
    # over two files that were never eval results. The likeliest way in is this command's own
    # --format json output, which lands in the same directory as the results files.
    it "refuses a JSON object that is not an eval results file" do
      wrong = File.join(dir, "wrong.json")
      File.write(wrong, JSON.generate({ "baseline" => {}, "candidate" => {}, "new_failures" => [] }))
      result = run_raif_cli("evals:compare", baseline, wrong, "--fail-on-regression", "0")

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("is not a Raif eval results file")
      expect(result.stdout).not_to include("no regression")
    end

    it "refuses a JSON array rather than crashing on it" do
      array = File.join(dir, "array.json")
      File.write(array, "[1,2]")
      result = run_raif_cli("evals:compare", array, array)

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("is not a Raif eval results file")
      expect(result.output).not_to include("TypeError")
    end
  end

  # A missing require in this path is invisible to every other spec in the suite, since
  # rails_helper loads the engine before they run.
  it "runs without loading Rails" do
    result = run_raif_cli_reporting_rails("evals:compare", baseline, candidate)

    expect(result.stderr).to include("RAILS_DEFINED=false")
    expect(result.stdout).to include("NEW FAILURES (1)")
  end
end
