# frozen_string_literal: true

require "rails_helper"
require "fileutils"

RSpec.describe Raif::Evals::RunLog do
  let(:results_dir) { Rails.root.join("tmp", "run_log_spec") }
  let(:configuration) { { default_llm_model_key: :raif_test_llm, repeats: 2, cases: nil, sample: nil, seed: nil } }

  let(:plan_keys) do
    [
      ["MyEvalSet#first-abc123", nil, nil],
      ["MyEvalSet#second-def456", nil, nil],
      ["MyEvalSet#third-ghi789", nil, nil]
    ]
  end

  let(:plan) { Raif::Evals::RunPlan.new(keys: plan_keys) }

  let(:log) do
    described_class.start(results_dir: results_dir, basename: "eval_run_20240101_120000", run_at: "2024-01-01T12:00:00Z",
      configuration: configuration, plan: plan)
  end

  def eval_result(description:, eval_id:, eval_index: 0, case_id: nil, run_index: nil, passed: true)
    result = Raif::Evals::EvalResult.new(description: description, eval_id: eval_id, eval_index: eval_index, case_id: case_id,
      run_index: run_index)
    result.add_expectation_result(Raif::Evals::ExpectationResult.new(description: "an expectation", status: passed ? :passed : :failed))
    result
  end

  before { FileUtils.rm_rf(results_dir) }
  after { FileUtils.rm_rf(results_dir) }

  describe ".start" do
    it "writes a header line naming the run" do
      header = JSON.parse(File.readlines(log.path).first)

      expect(header["type"]).to eq("run")
      expect(header["run_at"]).to eq("2024-01-01T12:00:00Z")
      expect(header["configuration"]).to include("default_llm_model_key" => "raif_test_llm", "repeats" => 2)
    end

    # Without it the log says what a run has done but not what it owes, and any invocation that
    # drained its own work list would read as having finished the run.
    it "writes the plan the run set out to execute" do
      header = JSON.parse(File.readlines(log.path).first)

      expect(header["plan"]["version"]).to eq(Raif::Evals::RunPlan::VERSION)
      expect(header["plan"]["keys"]).to eq(plan_keys)
    end

    # Otherwise it would gain a second header and read back as one run.
    it "truncates a stale log left at the same path" do
      FileUtils.mkdir_p(results_dir)
      File.write(results_dir.join("eval_run_20240101_120000.partial.jsonl"), %({"type":"result","eval_set":"Old","result":{}}\n))

      expect(File.readlines(log.path).count).to eq(1)
      expect(described_class.resume(path: log.path, configuration: configuration, plan: plan).results_count).to eq(0)
    end

    it "names the log after the results file it will complete" do
      expect(log.path.basename.to_s).to eq("eval_run_20240101_120000.partial.jsonl")
      expect(log.results_path.basename.to_s).to eq("eval_run_20240101_120000.json")
    end
  end

  describe "#record" do
    it "appends one line per result and remembers what it holds" do
      log.record(eval_set: "MyEvalSet", result: eval_result(description: "first", eval_id: "MyEvalSet#first-abc123"))
      log.record(eval_set: "MyEvalSet",
        result: eval_result(description: "second", eval_id: "MyEvalSet#second-def456", eval_index: 1, case_id: "atom", run_index: 2))

      lines = File.readlines(log.path)
      expect(lines.count).to eq(3) # header plus two results

      expect(log.results_count).to eq(2)
      expect(log.results_for("MyEvalSet").map { |result| result[:description] }).to eq(["first", "second"])
      expect(log.recorded?(eval_id: "MyEvalSet#first-abc123")).to be true
      expect(log.recorded?(eval_id: "MyEvalSet#second-def456", case_id: "atom", run_index: 2)).to be true
    end

    it "does not consider a different case or repeat recorded" do
      log.record(eval_set: "MyEvalSet",
        result: eval_result(description: "first", eval_id: "MyEvalSet#first-abc123", case_id: "atom", run_index: 1))

      expect(log.recorded?(eval_id: "MyEvalSet#first-abc123", case_id: "monad", run_index: 1)).to be false
      expect(log.recorded?(eval_id: "MyEvalSet#first-abc123", case_id: "atom", run_index: 2)).to be false
      expect(log.recorded?(eval_id: "OtherEvalSet#first-abc123", case_id: "atom", run_index: 1)).to be false
    end
  end

  describe ".resume" do
    before do
      log.record(eval_set: "MyEvalSet", result: eval_result(description: "first", eval_id: "MyEvalSet#first-abc123"))
      log.record(eval_set: "MyEvalSet",
        result: eval_result(description: "second", eval_id: "MyEvalSet#second-def456", eval_index: 1, passed: false))
    end

    it "reads the recorded results back" do
      resumed = described_class.resume(path: log.path, configuration: configuration, plan: plan)

      expect(resumed.run_at).to eq("2024-01-01T12:00:00Z")
      expect(resumed.results_count).to eq(2)
      expect(resumed.results_for("MyEvalSet").map { |result| result[:description] }).to eq(["first", "second"])
      expect(resumed.recorded?(eval_id: "MyEvalSet#first-abc123")).to be true
      expect(resumed.recorded?(eval_id: "MyEvalSet#third-ghi789")).to be false
    end

    # Run's summary compares statuses against :passed.
    it "restores expectation statuses as symbols" do
      resumed = described_class.resume(path: log.path, configuration: configuration, plan: plan)

      statuses = resumed.results_for("MyEvalSet").flat_map { |result| result[:expectation_results].map { |e| e[:status] } }
      expect(statuses).to eq([:passed, :failed])
    end

    it "keeps appending to the same file" do
      resumed = described_class.resume(path: log.path, configuration: configuration, plan: plan)
      resumed.record(eval_set: "MyEvalSet", result: eval_result(description: "third", eval_id: "MyEvalSet#third-ghi789", eval_index: 2))

      expect(File.readlines(log.path).count).to eq(4)
      expect(described_class.resume(path: log.path, configuration: configuration, plan: plan).results_count).to eq(3)
    end

    it "refuses when the configuration differs, naming the keys that moved" do
      expect do
        described_class.resume(path: log.path, configuration: configuration.merge(repeats: 5, seed: 42), plan: plan)
      end.to raise_error(described_class::IncompatibleResumeError, /repeats: log has 2, this run has 5.*seed: log has nil, this run has 42/m)
    end

    describe "dataset and provenance keys" do
      let(:configuration) do
        {
          repeats: 2,
          datasets: [
            { eval_set: "SetA", name: "topics", cases: 3, digest: "sha256:aaa" },
            { eval_set: "SetB", name: "documents", cases: 4, digest: "sha256:bbb" }
          ],
          code: { git_sha: "a" * 40, dirty: false }
        }
      end

      it "refuses when a dataset both sides resolved fingerprints differently" do
        edited = configuration.merge(datasets: [
          { eval_set: "SetA", name: "topics", cases: 3, digest: "sha256:ccc" },
          { eval_set: "SetB", name: "documents", cases: 4, digest: "sha256:bbb" }
        ])

        expect { described_class.resume(path: log.path, configuration: edited, plan: plan) }.to raise_error(
          described_class::IncompatibleResumeError,
          /dataset topics in SetA: log has 3 cases \(sha256:aaa\), this run has 3 cases \(sha256:ccc\)/
        )
      end

      # What a resume narrowed to one eval set file looks like: it only resolved that file's
      # datasets, and the ones it never looked at are not evidence of anything.
      it "allows a resume that resolved only some of the logged datasets" do
        narrowed = configuration.merge(datasets: [{ eval_set: "SetB", name: "documents", cases: 4, digest: "sha256:bbb" }])

        expect { described_class.resume(path: log.path, configuration: narrowed, plan: plan) }.not_to raise_error
      end

      it "allows a resume that resolved a dataset the log does not hold" do
        widened = configuration.merge(datasets: configuration[:datasets] + [
          { eval_set: "SetC", name: "extra", cases: 1, digest: "sha256:ddd" }
        ])

        expect { described_class.resume(path: log.path, configuration: widened, plan: plan) }.not_to raise_error
      end

      # Insisting on the commit would strand the results of any run interrupted across one,
      # including the commit made to fix what interrupted it. Raif::Evals::Run warns instead.
      it "ignores the code the run was started against" do
        moved = configuration.merge(code: { git_sha: "b" * 40, dirty: true })

        expect { described_class.resume(path: log.path, configuration: moved, plan: plan) }.not_to raise_error
      end
    end

    it "does not treat a symbol and its serialized string as a difference" do
      expect { described_class.resume(path: log.path, configuration: configuration, plan: plan) }.not_to raise_error
    end

    # Keyed on nil, every pending execution would look already-recorded and the run would be
    # skipped and reported as complete.
    it "refuses a log whose results predate eval ids" do
      File.write(log.path, %({"type":"result","eval_set":"MyEvalSet","result":{"description":"first","passed":true}}\n), mode: "a")

      expect { described_class.resume(path: log.path, configuration: configuration, plan: plan) }
        .to raise_error(described_class::IncompatibleResumeError, /before evals had ids/)
    end

    it "refuses a file with no run header" do
      File.write(log.path, %({"type":"result","eval_set":"MyEvalSet","result":{}}\n))

      expect { described_class.resume(path: log.path, configuration: configuration, plan: plan) }
        .to raise_error(described_class::IncompatibleResumeError, /no run header/)
    end

    # What a hard kill mid-write leaves behind.
    it "skips a truncated final line rather than raising" do
      File.write(log.path, %({"type":"result","eval_set":"MyEvalSet","result":{"desc), mode: "a")

      resumed = described_class.resume(path: log.path, configuration: configuration, plan: plan)
      expect(resumed.results_count).to eq(2)
    end

    describe "the run plan" do
      it "carries the logged plan rather than the resuming invocation's" do
        narrowed = Raif::Evals::RunPlan.new(keys: [["MyEvalSet#third-ghi789", nil, nil]])
        resumed = described_class.resume(path: log.path, configuration: configuration, plan: narrowed)

        expect(resumed.plan.keys).to eq(plan_keys)
        expect(resumed.outstanding_keys).to eq([["MyEvalSet#third-ghi789", nil, nil]])
        expect(resumed.complete?).to be false
      end

      it "is complete once every planned execution has been recorded" do
        resumed = described_class.resume(path: log.path, configuration: configuration, plan: plan)
        resumed.record(eval_set: "MyEvalSet", result: eval_result(description: "third", eval_id: "MyEvalSet#third-ghi789", eval_index: 2))

        expect(resumed.complete?).to be true
      end

      # An eval block added to a file while the run was interrupted. Raif::Evals::Run warns about
      # the code moving rather than refusing, so the new eval runs - and the run is not finished
      # until it has.
      it "takes on work the run did not plan, and writes it back to the log" do
        widened = plan.plus([["MyEvalSet#fourth-jkl012", nil, nil]])
        resumed = described_class.resume(path: log.path, configuration: configuration, plan: widened)

        expect(resumed.plan.keys.last).to eq(["MyEvalSet#fourth-jkl012", nil, nil])

        reread = described_class.resume(path: log.path, configuration: configuration, plan: plan)
        expect(reread.plan.keys.last).to eq(["MyEvalSet#fourth-jkl012", nil, nil])
      end

      # The keys are how a resume tells finished work from outstanding work, so a log without them
      # cannot be finished safely - it can only be told what one invocation happened to look at.
      it "refuses a log that records no plan" do
        rewritten = File.readlines(log.path)
        rewritten[0] = JSON.generate(JSON.parse(rewritten[0]).except("plan")) + "\n"
        File.write(log.path, rewritten.join)

        expect { described_class.resume(path: log.path, configuration: configuration, plan: plan) }
          .to raise_error(described_class::IncompatibleResumeError, /records no run plan/)
      end

      it "refuses a plan written in a format it cannot read" do
        rewritten = File.readlines(log.path)
        rewritten[0] = JSON.generate(JSON.parse(rewritten[0]).merge("plan" => { "version" => 99, "keys" => [] })) + "\n"
        File.write(log.path, rewritten.join)

        expect { described_class.resume(path: log.path, configuration: configuration, plan: plan) }
          .to raise_error(described_class::IncompatibleResumeError, /cannot read/)
      end
    end
  end

  describe "#discard!" do
    it "removes the log" do
      log.discard!
      expect(File.exist?(log.path)).to be false
    end
  end
end
