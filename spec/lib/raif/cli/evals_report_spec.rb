# frozen_string_literal: true

require "rails_helper"
require "raif/cli"

# Driven through the real executable rather than by calling the command object, because the
# command's contract includes what it loads: it reads one JSON file and renders a template, and
# is required to do so without booting Rails.
RSpec.describe Raif::CLI::EvalsReport do
  around do |example|
    Dir.mktmpdir("raif-cli") do |dir|
      @dir = dir
      example.run
    end
  end

  attr_reader :dir

  let(:results) { write_payload(dir, "run.json", cli_results_payload(model: "gpt_a", passed: false, score_value: 3.0)) }

  it "writes an HTML report beside the results file" do
    result = run_raif_cli("evals:report", results)

    expect(result.exit_code).to eq(0)
    expect(result.stdout).to include("Run report written to: #{File.join(dir, "run.html")}")

    html = File.read(File.join(dir, "run.html"))
    expect(html).to include("Raif eval run")
    expect(html).to include("Failures (1)")
  end

  it "writes to --output when one is given" do
    target = File.join(dir, "nested", "report.html")
    FileUtils.mkdir_p(File.dirname(target))

    result = run_raif_cli("evals:report", results, "--output", target)

    expect(result.exit_code).to eq(0)
    expect(File.read(target)).to include("Raif eval run")
  end

  it "renders without booting Rails" do
    result = run_raif_cli_reporting_rails("evals:report", results)

    expect(result.exit_code).to eq(0)
    expect(result.stderr).to include("RAILS_DEFINED=false")
  end

  it "prints usage when no results file is given" do
    result = run_raif_cli("evals:report")

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("Usage: raif evals:report RESULTS.json")
  end

  it "rejects a format it cannot render" do
    result = run_raif_cli("evals:report", results, "--format", "pdf")

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("Usage: raif evals:report RESULTS.json")
  end

  it "names the missing file" do
    result = run_raif_cli("evals:report", File.join(dir, "absent.json"))

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("File not found")
  end

  it "says what a file has to be when it is JSON but not a results file" do
    path = write_payload(dir, "other.json", { "something" => "else" })

    result = run_raif_cli("evals:report", path)

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("is not a Raif eval results file")
  end

  # A run that stopped early writes no results file, so the log is the only thing to hand and
  # reaching for it is the obvious mistake. Its parse error says nothing about what to do next.
  it "points a partial run log at --resume rather than failing to parse it" do
    path = File.join(dir, "run.partial.jsonl")
    File.write(path, %({"type":"run"}\n{"type":"result"}\n))

    result = run_raif_cli("evals:report", path)

    expect(result.exit_code).to eq(1)
    expect(result.stdout).to include("is a partial run log")
    expect(result.stdout).to include("--resume")
  end
end
