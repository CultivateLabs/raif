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

  # Eight cases, every one of them worse: a sign test over eight matched pairs reaches p=0.0078,
  # which clears the 0.05 family-wise level split across the two candidate rows (the eval's pass
  # rate and the gated clarity score).
  describe "--fail-on-regression" do
    let(:cases) { %w[a b c d e f g h] }
    let(:wide_baseline) do
      write_payload(dir, "wide_a.json", cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0, case_ids: cases))
    end
    let(:wide_candidate) do
      write_payload(dir, "wide_b.json", cli_results_payload(model: "gpt_b", passed: false, score_value: 3.0, case_ids: cases))
    end

    it "exits 1 for a regression that is both large enough and consistent enough" do
      result = run_raif_cli("evals:compare", wide_baseline, wide_candidate, "--fail-on-regression", "0.25")

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("--fail-on-regression 0.25")
      expect(result.stdout).to include("8/8 cases worse")
      expect(result.stdout).to include("at a family-wise 0.05 over 2 candidate rows")
    end

    it "exits 0 when the regression is inside the threshold" do
      steady = write_payload(dir, "steady.json", cli_results_payload(model: "gpt_b", passed: true, score_value: 5.0, case_ids: cases))
      result = run_raif_cli("evals:compare", wide_baseline, steady, "--fail-on-regression", "0.25")

      expect(result.exit_code).to eq(0)
    end

    # The regression is as large as the one above, but measured on one case at one repeat. A gate
    # on effect size alone exits 1 here, which is how it comes to fire on noise.
    it "exits 0 for a large regression that a single case cannot distinguish from noise" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--fail-on-regression", "0.25")

      expect(result.exit_code).to eq(0)
      expect(result.stdout).to include("none distinguishable from run-to-run variation")
    end

    # ...and --significance 1 is the way back to gating on the point estimate alone.
    it "gates on effect size alone under --significance 1" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--fail-on-regression", "0.25", "--significance", "1")

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("evidence not required (--significance 1.0)")
    end

    it "rejects a significance level outside (0, 1]" do
      result = run_raif_cli("evals:compare", baseline, candidate, "--significance", "0")

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("--significance must be greater than 0 and at most 1")
    end
  end

  # Nothing the gate flagged could be tested, so it has no answer. Exiting 0 would report a run
  # that may well have regressed as clean.
  describe "insufficient evidence" do
    let(:no_dataset) do
      lambda do |name, model, score_value|
        payload = cli_results_payload(model: model, passed: true, score_value: score_value)
        payload["results"]["SummarizationEvalSet"].each { |result| result["case_id"] = nil }
        write_payload(dir, name, payload)
      end
    end

    it "refuses to pass or fail, and exits 2" do
      result = run_raif_cli(
        "evals:compare",
        no_dataset.call("nd_a.json", "gpt_a", 5.0),
        no_dataset.call("nd_b.json", "gpt_b", 3.0),
        "--fail-on-regression", "0.25"
      )

      expect(result.exit_code).to eq(2)
      expect(result.stdout).to include("Refusing to pass or fail")
      expect(result.stdout).to include("--significance 1 to gate on effect size alone")
    end

    it "gates anyway under --significance 1" do
      result = run_raif_cli(
        "evals:compare",
        no_dataset.call("nd_a.json", "gpt_a", 5.0),
        no_dataset.call("nd_b.json", "gpt_b", 3.0),
        "--fail-on-regression", "0.25", "--significance", "1"
      )

      expect(result.exit_code).to eq(1)
    end
  end

  # An error and a quality failure are different findings, and the gate has to treat them that
  # way or a rate-limited afternoon fails the build as a model regression.
  describe "runs that errored" do
    let(:cases) { %w[a b c d e f g h] }
    let(:clean_baseline) do
      write_payload(dir, "err_a.json", cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0, case_ids: cases))
    end

    # One of eight cases errored: 12.5%, above the 5% ceiling.
    let(:flaky_candidate) do
      write_payload(dir, "err_b.json",
        cli_results_payload(model: "gpt_b", passed: false, score_value: 3.0, case_ids: cases, errored_case_ids: ["a"]))
    end

    it "reports the error rate move in its own section" do
      result = run_raif_cli("evals:compare", clean_baseline, flaky_candidate)

      expect(result.exit_code).to eq(0)
      expect(result.stdout).to include("ERROR RATES (1)")
      expect(result.stdout).to include("0/8 -> 1/8 runs errored")
      expect(result.stdout).to include("evals errored")
    end

    it "reports the errored case as not comparable rather than as a new failure" do
      result = run_raif_cli("evals:compare", clean_baseline, flaky_candidate)

      expect(result.stdout).to include("candidate: all 1 run errored")
      # The seven cases that did produce a measurement are still diffed.
      expect(result.stdout).to include("NEW FAILURES (7)")
    end

    # A real regression is present here. The gate still declines, because it cannot rule out that
    # the run which errored was the one that would have changed the answer.
    it "refuses to gate when a side lost too many runs to errors, and exits 2" do
      result = run_raif_cli("evals:compare", clean_baseline, flaky_candidate, "--fail-on-regression", "0.25")

      expect(result.exit_code).to eq(2)
      expect(result.stdout).to include("too many runs errored to gate on this comparison")
      expect(result.stdout).to include("candidate: 12.5% of runs errored")
      expect(result.stdout).to include("ceiling:   5% (--max-error-rate)")
    end

    it "gates on the surviving runs under --max-error-rate 1" do
      result = run_raif_cli("evals:compare", clean_baseline, flaky_candidate,
        "--fail-on-regression", "0.25", "--max-error-rate", "1")

      expect(result.exit_code).to eq(1)
    end

    it "gates normally when the error rate is inside the ceiling" do
      twenty = ("a".."t").to_a
      inside_baseline = write_payload(dir, "in_a.json",
        cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0, case_ids: twenty))
      inside_candidate = write_payload(dir, "in_b.json",
        cli_results_payload(model: "gpt_b", passed: false, score_value: 3.0, case_ids: twenty, errored_case_ids: ["a"]))

      result = run_raif_cli("evals:compare", inside_baseline, inside_candidate, "--fail-on-regression", "0.25")

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("19/19 cases worse")
    end

    # Without a threshold there is no gate to decline, so the error rate is reported and nothing
    # more - the same shape as the other refusals, which only fire under --fail-on-regression.
    it "still exits 0 with no threshold set, however many runs errored" do
      result = run_raif_cli("evals:compare", clean_baseline, flaky_candidate)

      expect(result.exit_code).to eq(0)
      expect(result.stdout).not_to include("too many runs errored")
    end

    it "rejects a ceiling outside 0..1" do
      result = run_raif_cli("evals:compare", clean_baseline, flaky_candidate, "--max-error-rate", "1.5")

      expect(result.exit_code).to eq(1)
      expect(result.stdout).to include("--max-error-rate must be between 0 and 1")
    end
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

    # The report is in the file rather than on screen, and a dataset that changed under the
    # comparison is the one thing in it a reader has to see before reading the rest.
    it "warns on stdout about a changed dataset when the report went to a file" do
      dataset = ->(digest, cases) { [{ "eval_set" => "SummarizationEvalSet", "name" => "documents", "cases" => cases, "digest" => digest }] }
      original = write_payload(dir, "orig.json",
        cli_results_payload(model: "gpt_a", passed: true, score_value: 5.0, datasets: dataset.call("sha256:aaa", 1)))
      edited = write_payload(dir, "edited.json",
        cli_results_payload(model: "gpt_a", passed: false, score_value: 3.0, datasets: dataset.call("sha256:bbb", 2)))

      result = run_raif_cli("evals:compare", original, edited, "--format", "html")

      expect(result.exit_code).to eq(0)
      expect(result.stdout).to include("Warning: these two runs did not measure the same datasets:")
      expect(result.stdout).to include("documents (SummarizationEvalSet): 1 cases sha256:aaa -> 2 cases sha256:bbb")
      expect(result.stdout).to include("Comparison report written to:")
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
