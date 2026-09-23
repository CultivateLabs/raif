# frozen_string_literal: true

require "rails_helper"
require "fileutils"

# Driven through Raif::Evals::Run, since what matters is what the page shows at each point of a
# real run: the eval bodies below read the page while their own execution is in flight.
RSpec.describe Raif::Evals::LiveReport do
  let(:output) { StringIO.new }
  let(:results_dir) { Rails.root.join("raif_evals", "results") }
  let(:basename) { "eval_run_20240101_120000_#{Raif.config.default_llm_model_key}" }
  let(:log_path) { results_dir.join("#{basename}.partial.jsonl") }
  let(:results_path) { results_dir.join("#{basename}.json") }
  let(:report_path) { results_dir.join("#{basename}.html") }

  # The page as each eval body found it, in execution order.
  let(:pages) { [] }

  let(:reader) do
    path = report_path
    seen = pages
    -> { seen << (File.exist?(path) ? File.read(path) : nil) }
  end

  let(:eval_set) do
    read_page = reader

    Class.new(Raif::Evals::EvalSet) do
      eval "first eval" do
        read_page.call
        expect("passes") { true }
      end

      eval "second eval" do
        read_page.call
        expect("fails <b>loudly</b>") { false }
      end

      eval "third eval" do
        read_page.call
        expect("passes") { true }
      end
    end
  end

  before do
    Raif.config.evals_live_report = true
    allow(Time).to receive(:current).and_return(Time.new(2024, 1, 1, 12, 0, 0))
    [log_path, results_path, report_path].each { |path| FileUtils.rm_f(path) }
    stub_const("LiveReportEvalSet", eval_set)
  end

  after do
    [log_path, results_path, report_path].each { |path| FileUtils.rm_f(path) }
  end

  def run_evals(eval_set_classes = [LiveReportEvalSet], **options)
    run = Raif::Evals::Run.new(output: output, **options)
    allow(run).to receive(:discover_eval_sets).and_return(eval_set_classes)
    run.instance_variable_set(:@eval_sets, eval_set_classes)
    run.execute
  rescue SystemExit
    nil
  end

  # Visible text, so assertions do not depend on the markup between a label and its value.
  def text(html)
    html.gsub(/<script.*?<\/script>/m, "").gsub(/<style.*?<\/style>/m, "").gsub(/<[^>]+>/, " ").gsub(/\s+/, " ")
  end

  it "prints the page's path before the first eval" do
    run_evals

    expect(output.string).to include("Live report: raif_evals/results/#{basename}.html")
    expect(output.string.index("Live report:")).to be < output.string.index("Running LiveReportEvalSet")
  end

  it "shows what has completed, what is running, and what failed as the run continues" do
    run_evals

    first, second, third = pages

    expect(text(first)).to include("Completed 0 / 3")
    expect(text(first)).to include("Running now (1)")
    expect(text(first)).to include("first eval")

    expect(text(second)).to include("Completed 1 / 3")
    expect(text(second)).to include("Passed 1")

    expect(text(third)).to include("Completed 2 / 3")
    expect(text(third)).to include("Failed 1")
    expect(text(third)).to include("Failures (1)")
    expect(text(third)).to include("LiveReportEvalSet 2 / 3")
  end

  it "gives passed and failed as shares of what was measured" do
    run_evals

    expect(text(pages.last)).to include("Passed 1 (50%)")
    expect(text(pages.last)).to include("Failed 1 (50%)")
  end

  it "reloads itself while the run continues" do
    run_evals

    expect(pages.first).to include(%(<meta http-equiv="refresh" content="30">))
    expect(pages.first).to include("sessionStorage")
  end

  it "escapes what the evals put on the page" do
    run_evals

    expect(pages.last).to include("fails &lt;b&gt;loudly&lt;/b&gt;")
    expect(pages.last).not_to include("<b>loudly</b>")
  end

  it "lists the newest completed execution first" do
    run_evals

    completed = pages.last[/Completed executions.*/m]
    expect(completed.index("second eval")).to be < completed.index("first eval")
  end

  it "is replaced by the full run report when the run completes" do
    run_evals

    payload = JSON.parse(File.read(results_path))
    expected = Raif::Evals::RunReport.new(payload, label: File.basename(results_path)).render

    expect(File.read(report_path)).to eq(expected)
    expect(File.read(report_path)).not_to include("http-equiv=\"refresh\"")
    expect(output.string).to include("Run report written to: raif_evals/results/#{basename}.html")
  end

  it "leaves no temporary files behind" do
    run_evals

    expect(Dir.glob(results_dir.join(".#{basename}*"))).to be_empty
  end

  context "when the run is interrupted" do
    let(:interrupted) { [] }

    let(:eval_set) do
      read_page = reader
      raised = interrupted

      Class.new(Raif::Evals::EvalSet) do
        eval "first eval" do
          read_page.call
          expect("passes") { true }
        end

        eval "second eval" do
          if raised.empty?
            raised << true
            raise Interrupt
          end

          read_page.call
          expect("passes") { true }
        end
      end
    end

    it "shows the run as stopped, with the command that resumes it, and stops reloading" do
      run_evals

      page = File.read(report_path)
      expect(text(page)).to include("Stopped")
      expect(text(page)).to include("Run interrupted.")
      expect(text(page)).to include("1 of 2 planned executions did not run")
      expect(text(page)).to include("bundle exec raif evals --resume raif_evals/results/#{basename}.partial.jsonl")
      expect(page).not_to include("http-equiv=\"refresh\"")
      expect(text(page)).not_to include("Running now")
    end

    it "records the elapsed time of every invocation in the results file" do
      allow_any_instance_of(Raif::Evals::RunLog).to receive(:elapsed_seconds).and_return(61.04)

      run_evals
      run_evals(resume_path: log_path.to_s)

      expect(JSON.parse(File.read(results_path))["elapsed_seconds"]).to eq(61.0)
      expect(text(File.read(report_path))).to include("Elapsed 1m 01s")
    end

    it "counts the results already in the log when the run resumes" do
      run_evals
      pages.clear

      run_evals(resume_path: log_path.to_s)

      expect(text(pages.first)).to include("Completed 1 / 2")
      expect(File.read(report_path)).to eq(
        Raif::Evals::RunReport.new(JSON.parse(File.read(results_path)), label: File.basename(results_path)).render
      )
    end
  end

  context "when the run stops before recording anything" do
    let(:eval_set) do
      Class.new(Raif::Evals::EvalSet) do
        eval "first eval" do
          raise Interrupt
        end
      end
    end

    it "deletes the page along with the run log" do
      run_evals

      expect(File.exist?(log_path)).to be false
      expect(File.exist?(report_path)).to be false
    end
  end

  context "when the page cannot be written" do
    before do
      allow_any_instance_of(described_class).to receive(:write).and_raise(Errno::EACCES, "results directory")
    end

    it "warns once and finishes the run" do
      run_evals

      expect(output.string.scan("Live report disabled").count).to eq(1)
      expect(File.exist?(results_path)).to be true
      expect(output.string).not_to include("Run report written to")
    end
  end

  # Transactional tests would pin every worker to one connection and serialize them, so the
  # rewrites below would never overlap.
  context "when executions run concurrently" do
    self.use_transactional_tests = false

    let(:eval_set) do
      Class.new(Raif::Evals::EvalSet) do
        dataset(:cases) { (1..8).map { |i| { id: "case-#{i}", input: {} } } }

        eval "sleeps briefly", dataset: :cases do |_eval_case|
          sleep 0.01
          expect("passes") { true }
        end
      end
    end

    it "serializes the rewrites and ends on the full run report" do
      writes = []
      allow_any_instance_of(described_class).to receive(:write).and_wrap_original do |original, html|
        writes << html
        original.call(html)
      end

      run_evals(concurrency: 4)

      expect(writes.size).to eq(1 + 8 + 8 + 1) # start, each start and finish, then the full report
      expect(writes[0..-2]).to all(include("</html>"))
      expect(text(writes[-2])).to include("Completed 8 / 8")
      expect(text(writes[-2])).to include("Running now (0)")
      expect(File.read(report_path)).to eq(writes.last)
      expect(Dir.glob(results_dir.join(".#{basename}*"))).to be_empty
    end
  end

  describe "opening the page in a browser" do
    before do
      allow(Process).to receive(:spawn).and_return(4242)
      allow(Process).to receive(:detach)
    end

    it "does not open it unless asked to" do
      run_evals

      expect(Process).not_to have_received(:spawn)
    end

    it "opens it once, after the first write, when asked to" do
      Raif.config.evals_open_live_report = true
      launches = []
      allow(Process).to receive(:spawn) do |*command, **options|
        launches << { command: command, options: options, page_existed: File.exist?(command.last) }
        4242
      end

      run_evals

      expect(launches.size).to eq(1)
      expect(launches.first[:command].last).to eq(report_path.to_s)
      expect(launches.first[:page_existed]).to be true
      expect(launches.first[:options]).to eq(out: File::NULL, err: File::NULL)
      expect(Process).to have_received(:detach).with(4242)
    ensure
      Raif.config.evals_open_live_report = false
    end

    it "warns and carries on when the opener cannot be launched" do
      Raif.config.evals_open_live_report = true
      allow(Process).to receive(:spawn).and_raise(Errno::ENOENT, "xdg-open")

      run_evals

      expect(output.string).to include("Could not open the live report in a browser")
      expect(File.exist?(results_path)).to be true
    ensure
      Raif.config.evals_open_live_report = false
    end

    it "opens nothing when the live report is turned off" do
      Raif.config.evals_live_report = false
      Raif.config.evals_open_live_report = true

      run_evals

      expect(Process).not_to have_received(:spawn)
    ensure
      Raif.config.evals_open_live_report = false
    end
  end

  context "when the live report is turned off" do
    before { Raif.config.evals_live_report = false }

    it "writes no page at any point" do
      run_evals

      expect(pages).to eq([nil, nil, nil])
      expect(File.exist?(report_path)).to be false
      expect(output.string).not_to include("Live report:")
    end
  end

  describe "the estimate of the time left" do
    let(:clock) { [0.0] }
    let(:plan) { Raif::Evals::RunPlan.new(keys: (1..10).map { |i| ["TimedEvalSet#eval-#{i}", nil, nil] }) }
    let(:run_log) do
      Raif::Evals::RunLog.start(results_dir: Rails.root.join("tmp", "live_report_spec"), basename: "timed",
        run_at: "2024-01-01T12:00:00Z", configuration: {}, plan: plan)
    end

    let(:report) do
      described_class.new(path: Rails.root.join("tmp", "live_report_spec", "timed.html"), run_log: run_log, configuration: {},
        concurrency: 2, output: output)
    end

    let(:pages_written) { [] }

    before do
      now = clock
      allow(report).to receive(:monotonic_now) { now.first }
      allow(report).to receive(:write) { |html| pages_written << html }
    end

    after { FileUtils.rm_rf(Rails.root.join("tmp", "live_report_spec")) }

    def execution(index)
      Raif::Evals::Execution.new(eval_definition: double(id: "TimedEvalSet#eval-#{index}", description: "eval #{index}"))
    end

    # Each execution takes 10 seconds on the stubbed clock.
    def finish(index)
      report.execution_started(execution(index), eval_set_name: "TimedEvalSet")
      clock[0] += 10
      report.execution_finished(execution(index))
    end

    it "waits for enough timed executions, then spreads the remaining work over the workers" do
      report.start!(executions: 10)

      finish(1)
      finish(2)
      expect(text(pages_written.last)).to include("Time left -")

      finish(3)
      # 7 left at 10 seconds each, over 2 workers.
      expect(text(pages_written.last)).to include("Time left ~35s")
    end
  end
end
