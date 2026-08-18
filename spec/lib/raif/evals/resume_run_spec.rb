# frozen_string_literal: true

require "rails_helper"
require "fileutils"

# Covers the round trip: the log a dying run leaves behind, and the run that picks it up.
RSpec.describe "Resuming an interrupted eval run" do
  let(:output) { StringIO.new }
  let(:results_dir) { Rails.root.join("raif_evals", "results") }
  let(:log_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.partial.jsonl") }
  let(:results_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json") }

  # Counts executions of the eval bodies, which is what a resume avoids paying for twice.
  let(:executions) { [] }

  let(:first_eval_set) do
    counter = executions
    Class.new(Raif::Evals::EvalSet) do
      define_method(:executions) { counter }

      eval "first eval" do
        executions << "first"
        expect("passes") { true }
      end

      eval "second eval" do
        executions << "second"
        expect("passes") { true }
      end
    end
  end

  # Raised once, so the resume that follows reaches the eval for real.
  let(:interrupted) { [] }

  let(:second_eval_set) do
    counter = executions
    raised = interrupted

    Class.new(Raif::Evals::EvalSet) do
      define_method(:executions) { counter }

      eval "third eval" do
        if raised.empty?
          raised << true
          raise Interrupt
        end

        executions << "third"
        expect("passes") { true }
      end
    end
  end

  before do
    allow(Time).to receive(:current).and_return(Time.new(2024, 1, 1, 12, 0, 0))
    # The other eval specs stub the same clock, so they write to these same two paths, and
    # whether this run left a results file behind is under test here.
    FileUtils.rm_f(log_path)
    FileUtils.rm_f(results_path)

    stub_const("ResumeFirstEvalSet", first_eval_set)
    stub_const("ResumeSecondEvalSet", second_eval_set)
    allow_any_instance_of(Raif::Evals::Run).to receive(:discover_eval_sets).and_return([ResumeFirstEvalSet, ResumeSecondEvalSet])
  end

  after do
    FileUtils.rm_f(log_path)
    FileUtils.rm_f(results_path)
  end

  # Interrupt, not StandardError: an eval block raising one of those is caught and recorded as
  # an errored expectation, so what kills a run is an Interrupt escaping one.
  def interrupt_after_first_set
    Raif::Evals::Run.new(output: output).execute
  rescue SystemExit
    nil
  end

  it "keeps the results of the sets that finished, and tells the user how to resume" do
    interrupt_after_first_set

    expect(executions).to eq(["first", "second"])
    expect(File.exist?(results_path)).to be false
    expect(File.exist?(log_path)).to be true

    recorded = File.readlines(log_path).drop(1).map { |line| JSON.parse(line) }
    expect(recorded.map { |line| line.dig("result", "description") }).to eq(["first eval", "second eval"])

    expect(output.string).to include("Run interrupted.")
    expect(output.string).to include("2 results were recorded before it stopped")
    expect(output.string).to include("--resume raif_evals/results/eval_run_20240101_120000")
  end

  it "runs only what the log does not already hold, and exports every result together" do
    interrupt_after_first_set
    executions.clear

    resumed_output = StringIO.new
    Raif::Evals::Run.new(output: resumed_output, resume_path: log_path.to_s).execute

    expect(executions).to eq(["third"])

    payload = JSON.parse(File.read(results_path))
    expect(payload["results"]["ResumeFirstEvalSet"].map { |r| r["description"] }).to eq(["first eval", "second eval"])
    expect(payload["results"]["ResumeSecondEvalSet"].map { |r| r["description"] }).to eq(["third eval"])
    expect(payload["summary"]).to include("total_evals" => 3, "passed_evals" => 3, "total_expectations" => 3,
      "passed_expectations" => 3)
    # Still the timestamp the log was opened with, not the resume's.
    expect(payload["run_at"]).to eq(Time.new(2024, 1, 1, 12, 0, 0).iso8601)
  end

  it "removes the log once the results file exists" do
    interrupt_after_first_set
    Raif::Evals::Run.new(output: StringIO.new, resume_path: log_path.to_s).execute

    expect(File.exist?(results_path)).to be true
    expect(File.exist?(log_path)).to be false
  end

  it "carries results forward for a set the resumed invocation never visits" do
    interrupt_after_first_set

    resumed = Raif::Evals::Run.new(output: StringIO.new, resume_path: log_path.to_s)
    allow(resumed).to receive(:discover_eval_sets).and_return([ResumeSecondEvalSet])
    resumed.instance_variable_set(:@eval_sets, [ResumeSecondEvalSet])
    resumed.execute

    expect(resumed.results.keys).to contain_exactly("ResumeFirstEvalSet", "ResumeSecondEvalSet")
  end

  # Logged results are matched to pending executions by eval id, which does not move when the file
  # is edited. Keyed on position, the inserted eval would inherit index 0's recorded result and be
  # skipped, while the two evals that did run would be paid for again.
  it "skips the results it already holds even when an eval was inserted above them" do
    interrupt_after_first_set
    executions.clear

    counter = executions
    edited_first_eval_set = Class.new(Raif::Evals::EvalSet) do
      define_method(:executions) { counter }

      eval "an eval added at the top" do
        executions << "added"
        expect("passes") { true }
      end

      eval "first eval" do
        executions << "first"
        expect("passes") { true }
      end

      eval "second eval" do
        executions << "second"
        expect("passes") { true }
      end
    end

    stub_const("ResumeFirstEvalSet", edited_first_eval_set)

    resumed = Raif::Evals::Run.new(output: StringIO.new, resume_path: log_path.to_s)
    allow(resumed).to receive(:discover_eval_sets).and_return([edited_first_eval_set, ResumeSecondEvalSet])
    resumed.instance_variable_set(:@eval_sets, [edited_first_eval_set, ResumeSecondEvalSet])
    resumed.execute

    expect(executions).to eq(["added", "third"])

    payload = JSON.parse(File.read(results_path))
    expect(payload["results"]["ResumeFirstEvalSet"].map { |r| r["description"] })
      .to contain_exactly("an eval added at the top", "first eval", "second eval")
  end

  it "refuses to resume into a run configured differently" do
    interrupt_after_first_set

    resumed = Raif::Evals::Run.new(output: output, resume_path: log_path.to_s, repeats: 3)

    expect { resumed.execute }.to raise_error(SystemExit)
    expect(output.string).to include("repeats: log has 1, this run has 3")
  end

  describe "part way through a dataset" do
    let(:dataset_eval_set) do
      counter = executions
      raised = interrupted

      Class.new(Raif::Evals::EvalSet) do
        define_method(:executions) { counter }

        dataset :topics do
          [{ id: "chicken", input: {} }, { id: "atom", input: {} }, { id: "monad", input: {} }]
        end

        eval "over the dataset", dataset: :topics do |eval_case|
          executions << eval_case.id

          if eval_case.id == "monad" && raised.empty?
            raised << true
            raise Interrupt
          end

          expect("passes") { true }
        end
      end
    end

    before do
      stub_const("ResumeDatasetEvalSet", dataset_eval_set)
      allow_any_instance_of(Raif::Evals::Run).to receive(:discover_eval_sets).and_return([ResumeDatasetEvalSet])
    end

    # The results either side of the interruption would describe different inputs under one case id,
    # which is the one thing the results file cannot express - unlike a changed model or judge, it
    # would not even show up as a mismatch to a later reader.
    it "refuses to resume when a dataset case was edited while the run was interrupted" do
      begin
        Raif::Evals::Run.new(output: StringIO.new).execute
      rescue SystemExit
        nil
      end

      counter = executions
      edited_dataset_eval_set = Class.new(Raif::Evals::EvalSet) do
        define_method(:executions) { counter }

        dataset :topics do
          [{ id: "chicken", input: { "asked" => "why" } }, { id: "atom", input: {} }, { id: "monad", input: {} }]
        end

        eval "over the dataset", dataset: :topics do |eval_case|
          executions << eval_case.id
          expect("passes") { true }
        end
      end

      stub_const("ResumeDatasetEvalSet", edited_dataset_eval_set)

      resumed = Raif::Evals::Run.new(output: output, resume_path: log_path.to_s)
      allow(resumed).to receive(:discover_eval_sets).and_return([edited_dataset_eval_set])
      resumed.instance_variable_set(:@eval_sets, [edited_dataset_eval_set])

      expect { resumed.execute }.to raise_error(SystemExit)
      expect(output.string).to include("dataset topics in ResumeDatasetEvalSet")
      expect(output.string).to include("Refusing to resume")
    end

    # A resume narrowed to one eval set file resolves only that file's datasets. Refusing over the
    # ones this invocation never looked at would make --resume unusable with a file argument.
    it "resumes an invocation that never resolves the dataset at all" do
      begin
        Raif::Evals::Run.new(output: StringIO.new).execute
      rescue SystemExit
        nil
      end

      resumed = Raif::Evals::Run.new(output: output, resume_path: log_path.to_s)
      allow(resumed).to receive(:discover_eval_sets).and_return([ResumeFirstEvalSet])
      resumed.instance_variable_set(:@eval_sets, [ResumeFirstEvalSet])
      resumed.execute

      expect(output.string).not_to include("Refusing to resume")
      expect(resumed.results.keys).to include("ResumeDatasetEvalSet")
    end

    it "resumes at the case it died on, keeping the ones already bought" do
      begin
        Raif::Evals::Run.new(output: output).execute
      rescue SystemExit
        nil
      end

      expect(executions).to eq(["chicken", "atom", "monad"])
      # The case that died is not in the log: a result is recorded once it completes.
      expect(output.string).to include("2 results were recorded before it stopped")

      executions.clear
      Raif::Evals::Run.new(output: StringIO.new, resume_path: log_path.to_s).execute

      expect(executions).to eq(["monad"])

      payload = JSON.parse(File.read(results_path))
      expect(payload["results"]["ResumeDatasetEvalSet"].map { |r| r["case_id"] }).to eq(["chicken", "atom", "monad"])
      expect(payload["summary"]["eval_pass_rates"].first["per_case"].map { |c| c["case_id"] })
        .to eq(["chicken", "atom", "monad"])
    end
  end

  # A warning rather than a refusal: the commit that landed while a run was interrupted is often the
  # one that fixed whatever interrupted it, and refusing would throw away results already paid for.
  it "warns but resumes when the code changed while the run was interrupted" do
    interrupt_after_first_set

    resumed = Raif::Evals::Run.new(output: output, resume_path: log_path.to_s)
    allow(Raif::Evals::RunLog).to receive(:logged_configuration)
      .and_return({ code: { git_sha: "a" * 40, dirty: false } })
    allow(resumed).to receive(:code_provenance).and_return({ git_sha: "b" * 40, dirty: true })
    resumed.execute

    expect(output.string).to include("Warning: the code has changed since this run started: aaaaaaaaaaaa -> bbbbbbbbbbbb (dirty)")
    expect(File.exist?(results_path)).to be true
  end

  it "does not warn about code when the run resumed against the same commit" do
    interrupt_after_first_set

    resumed = Raif::Evals::Run.new(output: output, resume_path: log_path.to_s)
    allow(Raif::Evals::RunLog).to receive(:logged_configuration)
      .and_return({ code: { git_sha: "a" * 40, dirty: false } })
    allow(resumed).to receive(:code_provenance).and_return({ git_sha: "a" * 40, dirty: false })
    resumed.execute

    expect(output.string).not_to include("the code has changed")
  end

  it "discards a log holding no results" do
    allow_any_instance_of(Raif::Evals::Run).to receive(:discover_eval_sets).and_return([ResumeSecondEvalSet])

    begin
      Raif::Evals::Run.new(output: output).execute
    rescue SystemExit
      nil
    end

    expect(File.exist?(log_path)).to be false
    expect(output.string).not_to include("--resume")
  end
end
