# frozen_string_literal: true

require "rails_helper"
require "fileutils"

# End-to-end coverage for `raif evals --concurrency N`.
#
# Transactional tests pin one connection to the whole pool and serialize every transaction taken
# on it, so under them the worker threads would take turns rather than overlap and nothing here
# would be testing what it claims to. Each eval still runs in its own transaction that is rolled
# back, so these examples leave no rows behind of their own.
RSpec.describe "Running evals concurrently" do
  self.use_transactional_tests = false

  let(:output) { StringIO.new }
  let(:results_dir) { Rails.root.join("raif_evals", "results") }
  let(:log_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.partial.jsonl") }
  let(:results_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json") }

  let(:started) { Queue.new }
  let(:release) { Queue.new }

  before do
    allow(Time).to receive(:current).and_return(Time.new(2024, 1, 1, 12, 0, 0))
    FileUtils.rm_f(log_path)
    FileUtils.rm_f(results_path)
  end

  after do
    FileUtils.rm_f(log_path)
    FileUtils.rm_f(results_path)
  end

  def run_with(eval_set_classes, **options)
    allow_any_instance_of(Raif::Evals::Run).to receive(:discover_eval_sets).and_return(Array(eval_set_classes))
    Raif::Evals::Run.new(output: output, **options)
  end

  describe "the fan-out" do
    let(:eval_set) do
      started_queue = started
      release_queue = release

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..6).map { |i| { id: "case-#{i}", input: {} } } }

        eval "blocks until released", dataset: :cases do |eval_case|
          started_queue << eval_case.id
          release_queue.pop
          expect("passes") { true }
        end
      end
    end

    before { stub_const("ConcurrentEvalSet", eval_set) }

    # The whole point of the feature: a case waiting on a provider response must not be stopping
    # the next case from having been sent yet.
    it "keeps `concurrency` cases in flight and no more" do
      run = run_with(ConcurrentEvalSet, concurrency: 3)
      runner = Thread.new { run.execute }

      expect(await_queue(started, 3).sort).to eq(["case-1", "case-2", "case-3"])
      expect(started).to be_empty

      6.times { release << :go }
      runner.join

      expect(run.results["ConcurrentEvalSet"].map { |result| result[:case_id] })
        .to eq(["case-1", "case-2", "case-3", "case-4", "case-5", "case-6"])
    end

    it "runs serially at the default concurrency" do
      run = run_with(ConcurrentEvalSet)
      runner = Thread.new { run.execute }

      expect(await_queue(started, 1)).to eq(["case-1"])
      expect(started).to be_empty

      6.times { release << :go }
      runner.join
    end
  end

  describe "captured model completions" do
    let(:eval_set) do
      started_queue = started
      release_queue = release

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { [{ id: "alpha", input: {} }, { id: "beta", input: {} }] }

        eval "calls the model", dataset: :cases do |eval_case|
          llm = Raif.llm(:raif_test_llm)
          llm.chat_handler = lambda do |_messages, _model_completion|
            started_queue << eval_case.id
            # Both cases sit inside their own LLM call at once, which is the only arrangement
            # in which one could capture the other's completion.
            release_queue.pop
            "#{eval_case.id} response"
          end

          llm.chat(message: "prompt for #{eval_case.id}")

          expect("passes") { true }
        end
      end
    end

    before do
      allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
      stub_const("CompletionCaptureEvalSet", eval_set)
    end

    it "gives each concurrent eval only the completions it made itself" do
      run = run_with(CompletionCaptureEvalSet, concurrency: 2)
      runner = Thread.new { run.execute }

      expect(await_queue(started, 2).sort).to eq(["alpha", "beta"])
      2.times { release << :go }
      runner.join

      results = run.results["CompletionCaptureEvalSet"].index_by { |result| result[:case_id] }

      ["alpha", "beta"].each do |case_id|
        completions = results[case_id][:model_completions]

        expect(completions.count).to eq(1)
        expect(completions.first[:response]).to eq("#{case_id} response")
        expect(results[case_id][:usage][:model_completions]).to eq(1)
      end
    end
  end

  describe "console output" do
    let(:eval_set) do
      release_queue = release

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..4).map { |i| { id: "case-#{i}", input: {} } } }

        eval "fails everywhere", dataset: :cases do |eval_case|
          # Every case is inside the eval block at once before any of them writes a line, so
          # a writer that did not buffer would interleave what follows.
          release_queue.pop
          expect("passes") { true }
          expect("#{eval_case.id} detail one") { false }
          expect("#{eval_case.id} detail two") { false }
        end
      end
    end

    before { stub_const("InterleavingEvalSet", eval_set) }

    it "keeps each case's summary and its failing expectations together in one block" do
      run = run_with(InterleavingEvalSet, concurrency: 4)
      runner = Thread.new { run.execute }

      4.times { release << :go }
      runner.join

      lines = output.string.gsub(/\e\[\d+m/, "").lines.map(&:rstrip)

      (1..4).each do |i|
        index = lines.index { |line| line.start_with?("  ✗ case-#{i} ") }

        expect(index).to be_present, "no summary line for case-#{i} in:\n#{output.string}"
        expect(lines[index + 1]).to eq("      ✗ case-#{i} detail one")
        expect(lines[index + 2]).to eq("      ✗ case-#{i} detail two")
      end
    end

    it "prints the eval set banner and the eval description once each" do
      run = run_with(InterleavingEvalSet, concurrency: 4)
      runner = Thread.new { run.execute }

      4.times { release << :go }
      runner.join

      plain = output.string.gsub(/\e\[\d+m/, "")

      expect(plain.scan("Running InterleavingEvalSet").count).to eq(1)
      expect(plain.scan(/^fails everywhere$/).count).to eq(1)
      expect(plain).to include("InterleavingEvalSet: 0/4 evals passed")
    end
  end

  describe "when interrupted" do
    let(:interrupted) { [] }
    let(:executions) { Queue.new }

    let(:eval_set) do
      executed = executions
      raised = interrupted
      release_queue = release

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..4).map { |i| { id: "case-#{i}", input: {} } } }

        eval "interrupts once", dataset: :cases do |eval_case|
          if eval_case.id == "case-1" && raised.empty?
            raised << true
            # Held until the other three cases are in the log, so what the interrupt is being
            # asked to preserve definitely exists by the time it lands.
            release_queue.pop
            raise Interrupt
          end

          executed << eval_case.id
          expect("passes") { true }
        end
      end
    end

    before { stub_const("InterruptedConcurrentEvalSet", eval_set) }

    def await_recorded_results(count, timeout: 10)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      until File.exist?(log_path) && File.readlines(log_path).drop(1).count >= count
        raise "timed out waiting for #{count} results in #{log_path}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.01
      end
    end

    # The run log is the only reason --resume exists, so an interrupt that lost the results
    # already paid for would be worse than not being able to interrupt at all.
    it "keeps what completed in the run log, and resumes into a complete results file" do
      runner = Thread.new do
        run_with(InterruptedConcurrentEvalSet, concurrency: 2).execute
      rescue SystemExit
        nil
      end

      await_recorded_results(3)
      release << :go
      runner.join

      expect(File).not_to exist(results_path)
      expect(File).to exist(log_path)
      expect(output.string).to include("Run interrupted.")
      expect(output.string).to include("--resume raif_evals/results/eval_run_20240101_120000")

      recorded = File.readlines(log_path).drop(1).map { |line| JSON.parse(line).dig("result", "case_id") }
      expect(recorded).to match_array(["case-2", "case-3", "case-4"])
      expect(Array.new(executions.size) { executions.pop }).to match_array(recorded)

      run_with(InterruptedConcurrentEvalSet, concurrency: 2, resume_path: log_path.to_s).execute

      # Only what the log did not already hold was paid for a second time.
      expect(Array.new(executions.size) { executions.pop }).to eq(["case-1"])

      payload = JSON.parse(File.read(results_path))
      expect(payload["results"]["InterruptedConcurrentEvalSet"].map { |result| result["case_id"] })
        .to eq(["case-1", "case-2", "case-3", "case-4"])
    end
  end

  describe "the results file" do
    let(:eval_set) do
      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { ["zulu", "alpha", "mike"].map { |id| { id: id, input: { "n" => id.length } } } }

        eval "over the dataset", dataset: :cases do |eval_case|
          # Enough of a stagger that completion order is not definition order.
          sleep(eval_case.id == "zulu" ? 0.03 : 0)
          expect("passes") { true }
          score "length", eval_case["n"]
        end

        eval "without a dataset" do
          expect("passes") { true }
        end
      end
    end

    before { stub_const("DeterministicEvalSet", eval_set) }

    it "is identical whatever concurrency produced it" do
      run_with(DeterministicEvalSet, concurrency: 1, repeats: 2).execute
      serial = JSON.parse(File.read(results_path))

      FileUtils.rm_f(results_path)

      run_with(DeterministicEvalSet, concurrency: 4, repeats: 2).execute
      concurrent = JSON.parse(File.read(results_path))

      expect(concurrent["results"]).to eq(serial["results"])
      expect(concurrent["summary"]).to eq(serial["summary"])
      # Dataset order, not alphabetical: the order is the dataset author's, and re-sorting on
      # the case id would silently replace it.
      expect(concurrent["results"]["DeterministicEvalSet"].filter_map { |result| result["case_id"] })
        .to eq(["zulu", "zulu", "alpha", "alpha", "mike", "mike"])
    end
  end

  describe "database connection pool validation" do
    it "refuses a concurrency the pool cannot serve, naming the setting to change" do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(5)

      expect { Raif::Evals::Run.new(output: output, concurrency: 5) }.to raise_error(SystemExit)
      expect(output.string).to include("Concurrency 5 needs a database connection pool larger than 5")
      expect(output.string).to include("config/database.yml")
    end

    it "allows a concurrency the pool can serve" do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(5)

      expect(Raif::Evals::Run.new(output: output, concurrency: 4).concurrency).to eq(4)
    end

    # Every eval runs in a transaction, and concurrent write transactions against one sqlite
    # file serialize on SQLITE_BUSY rather than going faster.
    it "caps sqlite at 1 rather than failing" do
      config = ActiveRecord::Base.connection_db_config
      allow(config).to receive(:adapter).and_return("sqlite3")
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)

      run = Raif::Evals::Run.new(output: output, concurrency: 8)

      expect(run.concurrency).to eq(1)
      expect(output.string).to include("Ignoring concurrency 8")
    end

    it "does not touch the database when running serially" do
      expect(ActiveRecord::Base).not_to receive(:connection_db_config)

      expect(Raif::Evals::Run.new(output: output).concurrency).to eq(1)
    end
  end
end
