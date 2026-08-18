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
      "RAIF_EVAL_RESUME", "RAIF_EVAL_CONCURRENCY", "RAIF_RUNNING_EVALS")
    original_verbose = Raif.config.evals_verbose_output

    example.run

    %w[RAIF_EVAL_REPEATS RAIF_EVAL_CASES RAIF_EVAL_SAMPLE RAIF_EVAL_SEED RAIF_EVAL_VERBOSE RAIF_EVAL_RESUME
       RAIF_EVAL_CONCURRENCY RAIF_RUNNING_EVALS].each do |key|
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

    expect(Raif::Evals::Run).to have_received(:new)
      .with(file_paths: nil, repeats: 1, cases: nil, sample: nil, seed: nil, resume_path: nil, concurrency: nil)
  end

  it "passes --repeat, --cases, --sample, --seed and --concurrency through" do
    run_cli(["--repeat", "3", "--cases", "climate-report, earnings-call", "--sample", "5", "--seed", "42", "--concurrency", "8"])

    expect(Raif::Evals::Run).to have_received(:new).with(
      file_paths: nil,
      repeats: 3,
      cases: ["climate-report", "earnings-call"],
      sample: 5,
      seed: 42,
      resume_path: nil,
      concurrency: 8
    )
  end

  # nil rather than 1, so Raif.config.evals_concurrency still decides when the flag is absent.
  it "leaves concurrency unset when neither the flag nor the environment names one" do
    run_cli([])

    expect(Raif::Evals::Run).to have_received(:new).with(hash_including(concurrency: nil))
  end

  it "lets --concurrency win over RAIF_EVAL_CONCURRENCY" do
    ENV["RAIF_EVAL_CONCURRENCY"] = "2"

    run_cli(["--concurrency", "6"])

    expect(Raif::Evals::Run).to have_received(:new).with(hash_including(concurrency: 6))
  end

  it "reads the environment equivalents of those flags" do
    ENV["RAIF_EVAL_REPEATS"] = "4"
    ENV["RAIF_EVAL_CASES"] = "atom,monad"
    ENV["RAIF_EVAL_SAMPLE"] = "2"
    ENV["RAIF_EVAL_SEED"] = "7"
    ENV["RAIF_EVAL_CONCURRENCY"] = "3"

    run_cli([])

    expect(Raif::Evals::Run).to have_received(:new)
      .with(file_paths: nil, repeats: 4, cases: ["atom", "monad"], sample: 2, seed: 7, resume_path: nil, concurrency: 3)
  end

  describe "--resume" do
    let(:log_path) { Rails.root.join("tmp", "eval_run_resume_cli.partial.jsonl") }

    before do
      FileUtils.mkdir_p(File.dirname(log_path))
      File.write(log_path, "{}\n")
    end

    after { FileUtils.rm_f(log_path) }

    it "passes the log path through" do
      run_cli(["--resume", log_path.to_s])

      expect(Raif::Evals::Run).to have_received(:new).with(hash_including(resume_path: log_path.to_s))
    end

    it "reads RAIF_EVAL_RESUME" do
      ENV["RAIF_EVAL_RESUME"] = log_path.to_s

      run_cli([])

      expect(Raif::Evals::Run).to have_received(:new).with(hash_including(resume_path: log_path.to_s))
    end

    it "rejects a missing log before booting the app" do
      cli = described_class.new(["--resume", "/nope/eval_run.partial.jsonl"])
      allow(cli).to receive(:load_rails_application)

      expect { cli.run }.to raise_error(SystemExit).and output(/Resume log not found/).to_stdout
      expect(cli).not_to have_received(:load_rails_application)
    end
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

  describe "invalid input" do
    # --sample 0 would run nothing and report an empty suite as a pass; a negative count
    # raises in Array#take.
    [["--sample", "0"], ["--sample", "-1"]].each do |flags|
      it "rejects #{flags.join(" ")} before booting the app" do
        cli = described_class.new(flags)
        allow(cli).to receive(:load_rails_application)

        expect { cli.run }.to raise_error(SystemExit).and output(/--sample must be 1 or greater/).to_stdout
        expect(cli).not_to have_received(:load_rails_application)
      end
    end

    it "rejects --concurrency 0 before booting the app" do
      cli = described_class.new(["--concurrency", "0"])
      allow(cli).to receive(:load_rails_application)

      expect { cli.run }.to raise_error(SystemExit).and output(/--concurrency must be 1 or greater/).to_stdout
      expect(cli).not_to have_received(:load_rails_application)
    end

    it "prints usage for an unparseable option rather than a backtrace" do
      cli = described_class.new(["--repeat", "many"])
      allow(cli).to receive(:load_rails_application)

      expect { cli.run }.to raise_error(SystemExit)
        .and output(/invalid argument: --repeat many.*Usage: raif evals/m).to_stdout
    end
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
