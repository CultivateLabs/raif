# frozen_string_literal: true

require "rails_helper"
require "fileutils"

RSpec.describe Raif::Evals::RunLog do
  let(:results_dir) { Rails.root.join("tmp", "run_log_spec") }
  let(:configuration) { { default_llm_model_key: :raif_test_llm, repeats: 2, cases: nil, sample: nil, seed: nil } }

  let(:log) do
    described_class.start(results_dir: results_dir, basename: "eval_run_20240101_120000", run_at: "2024-01-01T12:00:00Z",
      configuration: configuration)
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

    # Otherwise it would gain a second header and read back as one run.
    it "truncates a stale log left at the same path" do
      FileUtils.mkdir_p(results_dir)
      File.write(results_dir.join("eval_run_20240101_120000.partial.jsonl"), %({"type":"result","eval_set":"Old","result":{}}\n))

      expect(File.readlines(log.path).count).to eq(1)
      expect(described_class.resume(path: log.path, configuration: configuration).results_count).to eq(0)
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
      resumed = described_class.resume(path: log.path, configuration: configuration)

      expect(resumed.run_at).to eq("2024-01-01T12:00:00Z")
      expect(resumed.results_count).to eq(2)
      expect(resumed.results_for("MyEvalSet").map { |result| result[:description] }).to eq(["first", "second"])
      expect(resumed.recorded?(eval_id: "MyEvalSet#first-abc123")).to be true
      expect(resumed.recorded?(eval_id: "MyEvalSet#third-ghi789")).to be false
    end

    # Run's summary compares statuses against :passed.
    it "restores expectation statuses as symbols" do
      resumed = described_class.resume(path: log.path, configuration: configuration)

      statuses = resumed.results_for("MyEvalSet").flat_map { |result| result[:expectation_results].map { |e| e[:status] } }
      expect(statuses).to eq([:passed, :failed])
    end

    it "keeps appending to the same file" do
      resumed = described_class.resume(path: log.path, configuration: configuration)
      resumed.record(eval_set: "MyEvalSet", result: eval_result(description: "third", eval_id: "MyEvalSet#third-ghi789", eval_index: 2))

      expect(File.readlines(log.path).count).to eq(4)
      expect(described_class.resume(path: log.path, configuration: configuration).results_count).to eq(3)
    end

    it "refuses when the configuration differs, naming the keys that moved" do
      expect do
        described_class.resume(path: log.path, configuration: configuration.merge(repeats: 5, seed: 42))
      end.to raise_error(described_class::IncompatibleResumeError, /repeats: log has 2, this run has 5.*seed: log has nil, this run has 42/m)
    end

    it "does not treat a symbol and its serialized string as a difference" do
      expect { described_class.resume(path: log.path, configuration: configuration) }.not_to raise_error
    end

    # Keyed on nil, every pending execution would look already-recorded and the run would be
    # skipped and reported as complete.
    it "refuses a log whose results predate eval ids" do
      File.write(log.path, %({"type":"result","eval_set":"MyEvalSet","result":{"description":"first","passed":true}}\n), mode: "a")

      expect { described_class.resume(path: log.path, configuration: configuration) }
        .to raise_error(described_class::IncompatibleResumeError, /before evals had ids/)
    end

    it "refuses a file with no run header" do
      File.write(log.path, %({"type":"result","eval_set":"MyEvalSet","result":{}}\n))

      expect { described_class.resume(path: log.path, configuration: configuration) }
        .to raise_error(described_class::IncompatibleResumeError, /no run header/)
    end

    # What a hard kill mid-write leaves behind.
    it "skips a truncated final line rather than raising" do
      File.write(log.path, %({"type":"result","eval_set":"MyEvalSet","result":{"desc), mode: "a")

      resumed = described_class.resume(path: log.path, configuration: configuration)
      expect(resumed.results_count).to eq(2)
    end
  end

  describe "#discard!" do
    it "removes the log" do
      log.discard!
      expect(File.exist?(log.path)).to be false
    end
  end
end
