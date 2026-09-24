# frozen_string_literal: true

require "rails_helper"
require "fileutils"

# End-to-end coverage for `raif evals --concurrency N`.
#
# Concurrent evals run in forked worker processes, which open connections of their own and so
# cannot see a transaction the example holds open. Each eval still runs in its own transaction
# that is rolled back, so these examples leave no rows behind of their own.
RSpec.describe "Running evals concurrently" do
  self.use_transactional_tests = false

  let(:output) { StringIO.new }
  let(:results_dir) { Rails.root.join("raif_evals", "results") }
  let(:log_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.partial.jsonl") }
  let(:results_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json") }

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
      latch = process_latch

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..6).map { |i| { id: "case-#{i}", input: {} } } }

        eval "blocks until released", dataset: :cases do |eval_case|
          latch.signal(eval_case.id)
          latch.wait_for_release
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

      expect(process_latch.await(3)).to eq(["case-1", "case-2", "case-3"])
      sleep 0.1
      expect(process_latch.signalled.size).to eq(3)

      process_latch.release!
      runner.join

      expect(run.results["ConcurrentEvalSet"].map { |result| result[:case_id] })
        .to eq(["case-1", "case-2", "case-3", "case-4", "case-5", "case-6"])
    end

    it "runs serially at the default concurrency" do
      run = run_with(ConcurrentEvalSet)
      runner = Thread.new { run.execute }

      expect(process_latch.await(1)).to eq(["case-1"])
      sleep 0.1
      expect(process_latch.signalled.size).to eq(1)

      process_latch.release!
      runner.join
    end
  end

  describe "captured model completions" do
    let(:eval_set) do
      latch = process_latch

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { [{ id: "alpha", input: {} }, { id: "beta", input: {} }] }

        eval "calls the model", dataset: :cases do |eval_case|
          llm = Raif.llm(:raif_test_llm)
          llm.chat_handler = lambda do |_messages, _model_completion|
            latch.signal(eval_case.id)
            # Both cases sit inside their own LLM call at once.
            latch.wait_for_release
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

      expect(process_latch.await(2)).to eq(["alpha", "beta"])
      process_latch.release!
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
      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..4).map { |i| { id: "case-#{i}", input: {} } } }

        eval "fails everywhere", dataset: :cases do |eval_case|
          expect("passes") { true }
          expect("#{eval_case.id} detail one") { false }
          expect("#{eval_case.id} detail two") { false }
        end
      end
    end

    before { stub_const("InterleavingEvalSet", eval_set) }

    it "keeps each case's summary and its failing expectations together in one block" do
      run_with(InterleavingEvalSet, concurrency: 4).execute

      lines = output.string.gsub(/\e\[\d+m/, "").lines.map(&:rstrip)

      (1..4).each do |i|
        index = lines.index { |line| line.start_with?("  ✗ case-#{i} ") }

        expect(index).to be_present, "no summary line for case-#{i} in:\n#{output.string}"
        expect(lines[index + 1]).to eq("      ✗ case-#{i} detail one")
        expect(lines[index + 2]).to eq("      ✗ case-#{i} detail two")
      end
    end

    it "prints the eval set banner and the eval description once each" do
      run_with(InterleavingEvalSet, concurrency: 4).execute

      plain = output.string.gsub(/\e\[\d+m/, "")

      expect(plain.scan("Running InterleavingEvalSet").count).to eq(1)
      expect(plain.scan(/^fails everywhere$/).count).to eq(1)
      expect(plain).to include("InterleavingEvalSet: 0/4 evals passed")
    end
  end

  # The reason worker processes exist: each execution runs in a transaction that is rolled back, and
  # two of them sharing a connection's database would take turns on any unique key they both write.
  describe "database isolation" do
    let(:eval_set) do
      latch = process_latch

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..2).map { |i| { id: "case-#{i}", input: {} } } }

        eval "writes the same unique key as every other case", dataset: :cases do |eval_case|
          connection = ActiveRecord::Base.connection
          # key is a reserved word in MySQL.
          connection.execute(<<~SQL)
            INSERT INTO active_storage_blobs (#{connection.quote_column_name("key")}, filename, byte_size, service_name, created_at)
            VALUES ('shared-key', 'shared.txt', 1, 'test', CURRENT_TIMESTAMP)
          SQL
          latch.signal(eval_case.id)
          latch.wait_for_release
          expect("passes") { true }
        end
      end
    end

    before { stub_const("SharedKeyEvalSet", eval_set) }

    # Creates and loads raif_dummy_test_1 and raif_dummy_test_2 on first use, as a real run would.
    it "runs each worker on a database of its own when the evals database is enabled" do
      allow(Raif::EvalsDatabase).to receive(:enabled?).and_return(true)

      run = run_with(SharedKeyEvalSet, concurrency: 2)
      runner = Thread.new { run.execute }

      # Both cases are past the insert at once, which one shared database would not allow.
      expect(process_latch.await(2, timeout: 60)).to eq(["case-1", "case-2"])
      process_latch.release!
      runner.join

      expect(run.results["SharedKeyEvalSet"].map { |result| result[:passed] }).to eq([true, true])
    end

    it "shares the run's database when the evals database is disabled" do
      allow(Raif::EvalsDatabase).to receive(:enabled?).and_return(false)
      allow(Raif::EvalsDatabase).to receive(:use_worker_database!)

      run = run_with(SharedKeyEvalSet, concurrency: 2)
      runner = Thread.new { run.execute }

      # The second case waits on the first one's uncommitted row, so only one gets past the insert.
      expect(process_latch.await(1)).to eq(["case-1"]).or eq(["case-2"])
      sleep 0.2
      expect(process_latch.signalled.size).to eq(1)

      process_latch.release!
      runner.join

      expect(Raif::EvalsDatabase).not_to have_received(:use_worker_database!)
    end
  end

  describe "the run header" do
    let(:eval_set) do
      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..3).map { |i| { id: "case-#{i}", input: {} } } }

        eval "passes", dataset: :cases do
          expect("passes") { true }
        end
      end
    end

    before do
      stub_const("HeaderEvalSet", eval_set)
      allow(Raif::EvalsDatabase).to receive(:enabled?).and_return(true)
      allow(Raif::EvalsDatabase).to receive(:use_worker_database!)
    end

    it "names only the worker databases the run uses when it has fewer executions than workers" do
      run_with(HeaderEvalSet, concurrency: 8).execute

      expect(output.string).to include("Concurrency: 8 (one database per worker, suffixed _1 to _3)")
    end
  end

  describe "when interrupted" do
    let(:eval_set) do
      latch = process_latch

      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..4).map { |i| { id: "case-#{i}", input: {} } } }

        eval "interrupts once", dataset: :cases do |eval_case|
          if eval_case.id == "case-1" && latch.signalled(stage: "raised").empty?
            latch.signal(eval_case.id, stage: "raised")
            # Held until the other three cases are in the log, so what the interrupt is being
            # asked to preserve definitely exists by the time it lands.
            latch.wait_for_release
            raise Interrupt
          end

          latch.signal(eval_case.id, stage: "executed")
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
      process_latch.release!
      runner.join

      expect(File).not_to exist(results_path)
      expect(File).to exist(log_path)
      expect(output.string).to include("Run interrupted.")
      expect(output.string).to include("--resume raif_evals/results/eval_run_20240101_120000")

      recorded = File.readlines(log_path).drop(1).map { |line| JSON.parse(line).dig("result", "case_id") }
      expect(recorded).to match_array(["case-2", "case-3", "case-4"])
      expect(process_latch.signalled(stage: "executed")).to match_array(recorded)

      process_latch.clear(stage: "executed")
      run_with(InterruptedConcurrentEvalSet, concurrency: 2, resume_path: log_path.to_s).execute

      # Only what the log did not already hold was paid for a second time.
      expect(process_latch.signalled(stage: "executed")).to eq(["case-1"])

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

  describe "when concurrency is not possible" do
    def stub_adapter(adapter, database: "db/test.sqlite3")
      config = ActiveRecord::Base.connection_db_config
      allow(config).to receive_messages(adapter: adapter, database: database)
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(config)
    end

    it "runs serially where the platform cannot fork" do
      allow(Process).to receive(:respond_to?).and_call_original
      allow(Process).to receive(:respond_to?).with(:fork).and_return(false)

      run = Raif::Evals::Run.new(output: output, concurrency: 4)

      expect(run.concurrency).to eq(1)
      expect(output.string).to include("Ignoring concurrency 4: this platform cannot fork worker processes")
    end

    # The workers would share one file, and concurrent write transactions against it serialize on
    # SQLITE_BUSY rather than going faster.
    it "runs serially on sqlite3 without an evals database per worker" do
      stub_adapter("sqlite3")
      allow(Raif::EvalsDatabase).to receive(:enabled?).and_return(false)

      run = Raif::Evals::Run.new(output: output, concurrency: 8)

      expect(run.concurrency).to eq(1)
      expect(output.string).to include("Ignoring concurrency 8: the workers would share one sqlite3 file")
      expect(output.string).to include("evals_database_suffix")
    end

    it "runs concurrently on sqlite3 when each worker gets a database file of its own" do
      stub_adapter("sqlite3")
      allow(Raif::EvalsDatabase).to receive(:enabled?).and_return(true)

      expect(Raif::Evals::Run.new(output: output, concurrency: 8).concurrency).to eq(8)
    end

    it "runs serially on an in-memory sqlite3 database, which a worker cannot share" do
      stub_adapter("sqlite3", database: ":memory:")
      allow(Raif::EvalsDatabase).to receive(:enabled?).and_return(true)

      run = Raif::Evals::Run.new(output: output, concurrency: 8)

      expect(run.concurrency).to eq(1)
      expect(output.string).to include("an in-memory sqlite3 database cannot be shared")
    end

    it "does not touch the database when running serially" do
      expect(ActiveRecord::Base).not_to receive(:connection_db_config)

      expect(Raif::Evals::Run.new(output: output).concurrency).to eq(1)
    end
  end
end
