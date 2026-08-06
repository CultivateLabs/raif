# frozen_string_literal: true

require "rails_helper"
require "raif/cli"

# Exercised in-process: unlike evals:compare, this command's job is to boot the host app and
# spend money, so what is worth pinning down is how it turns flags and environment variables
# into the arguments Run receives.
RSpec.describe Raif::CLI::Evals do
  let(:eval_run) { instance_double(Raif::Evals::Run, execute: nil) }

  around do |example|
    original_env = ENV.to_h.slice("RAIF_EVAL_REPEATS", "RAIF_EVAL_CASES", "RAIF_EVAL_SAMPLE", "RAIF_EVAL_SEED", "RAIF_EVAL_VERBOSE",
      "RAIF_RUNNING_EVALS")
    original_verbose = Raif.config.evals_verbose_output

    example.run

    %w[RAIF_EVAL_REPEATS RAIF_EVAL_CASES RAIF_EVAL_SAMPLE RAIF_EVAL_SEED RAIF_EVAL_VERBOSE RAIF_RUNNING_EVALS].each do |key|
      original_env.key?(key) ? ENV[key] = original_env[key] : ENV.delete(key)
    end
    Raif.config.evals_verbose_output = original_verbose
  end

  # Stops short of load_rails_application: the app is already booted in the spec process, and
  # calling it would chdir out of the dummy app.
  def run_cli(args)
    cli = described_class.new(args)
    allow(cli).to receive(:load_rails_application)
    allow(Raif::Evals::Run).to receive(:new).and_return(eval_run)
    cli.run
    cli
  end

  it "defaults to one repeat and no case selection" do
    run_cli([])

    expect(Raif::Evals::Run).to have_received(:new).with(file_paths: nil, repeats: 1, cases: nil, sample: nil, seed: nil)
  end

  it "passes --repeat, --cases, --sample and --seed through" do
    run_cli(["--repeat", "3", "--cases", "climate-report, earnings-call", "--sample", "5", "--seed", "42"])

    expect(Raif::Evals::Run).to have_received(:new).with(
      file_paths: nil,
      repeats: 3,
      cases: ["climate-report", "earnings-call"],
      sample: 5,
      seed: 42
    )
  end

  it "reads the environment equivalents of those flags" do
    ENV["RAIF_EVAL_REPEATS"] = "4"
    ENV["RAIF_EVAL_CASES"] = "atom,monad"
    ENV["RAIF_EVAL_SAMPLE"] = "2"
    ENV["RAIF_EVAL_SEED"] = "7"

    run_cli([])

    expect(Raif::Evals::Run).to have_received(:new).with(file_paths: nil, repeats: 4, cases: ["atom", "monad"], sample: 2, seed: 7)
  end

  it "lets a flag win over the environment" do
    ENV["RAIF_EVAL_REPEATS"] = "4"

    run_cli(["--repeat", "9"])

    expect(Raif::Evals::Run).to have_received(:new).with(hash_including(repeats: 9))
  end

  it "splits a file path from its line number" do
    run_cli(["./raif_evals/eval_sets/a_eval_set.rb:23", "./raif_evals/eval_sets/b_eval_set.rb"])

    expect(Raif::Evals::Run).to have_received(:new).with(hash_including(file_paths: [
      { file_path: "./raif_evals/eval_sets/a_eval_set.rb", line_number: 23 },
      { file_path: "./raif_evals/eval_sets/b_eval_set.rb", line_number: nil }
    ]))
  end

  it "marks the process as running evals" do
    run_cli([])

    expect(ENV.fetch("RAIF_RUNNING_EVALS", nil)).to eq("true")
  end

  describe "verbose output" do
    it "leaves the configured value alone when neither flag is given" do
      Raif.config.evals_verbose_output = true

      run_cli([])

      expect(Raif.config.evals_verbose_output).to be(true)
    end

    it "turns verbose on with --verbose" do
      Raif.config.evals_verbose_output = false

      run_cli(["--verbose"])

      expect(Raif.config.evals_verbose_output).to be(true)
    end

    # An app whose initializer sets evals_verbose_output would otherwise have no way to reach
    # the compact dataset output.
    it "turns verbose off with --no-verbose" do
      Raif.config.evals_verbose_output = true

      run_cli(["--no-verbose"])

      expect(Raif.config.evals_verbose_output).to be(false)
    end

    it "reads RAIF_EVAL_VERBOSE" do
      Raif.config.evals_verbose_output = false
      ENV["RAIF_EVAL_VERBOSE"] = "1"

      run_cli([])

      expect(Raif.config.evals_verbose_output).to be(true)
    end

    it "treats RAIF_EVAL_VERBOSE=0 as off" do
      Raif.config.evals_verbose_output = true
      ENV["RAIF_EVAL_VERBOSE"] = "0"

      run_cli([])

      expect(Raif.config.evals_verbose_output).to be(false)
    end

    it "lets --verbose win over RAIF_EVAL_VERBOSE=0" do
      Raif.config.evals_verbose_output = false
      ENV["RAIF_EVAL_VERBOSE"] = "0"

      run_cli(["--verbose"])

      expect(Raif.config.evals_verbose_output).to be(true)
    end
  end
end
