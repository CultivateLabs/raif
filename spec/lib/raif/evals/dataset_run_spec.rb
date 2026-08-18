# frozen_string_literal: true

require "rails_helper"
require "fileutils"

# End-to-end coverage for a dataset eval: DSL, per-case results, score aggregation, and
# results export, all against a stubbed LLM.
RSpec.describe "Running a dataset eval set" do
  let(:output) { StringIO.new }
  let(:eval_set_path) { Rails.root.join("raif_evals", "eval_sets", "dataset_example_eval_set.rb").to_s }
  let(:run) { Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 2) }

  before do
    allow(Time).to receive(:current).and_return(Time.new(2024, 1, 1, 12, 0, 0))

    stub_raif_task(Raif::TestTask) do |_messages, _model_completion|
      "Why did the chicken cross the road?"
    end

    stub_raif_task(Raif::Evals::LlmJudges::Scored) do |_messages, _model_completion|
      { score: 5, reasoning: "Clear enough", confidence: 0.9 }.to_json
    end
  end

  after do
    FileUtils.rm_f(Rails.root.join("raif_evals", "results", "eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json"))
  end

  it "runs the eval body once per case per repeat and tags each result with its case" do
    run.execute

    results = run.results["Raif::Evals::DatasetExampleEvalSet"]
    dataset_results = results.select { |result| result[:case_id] }

    expect(dataset_results.count).to eq(6)
    expect(dataset_results.map { |result| [result[:case_id], result[:run_index]] }).to eq([
      ["chicken", 1], ["chicken", 2],
      ["atom", 1], ["atom", 2],
      ["monad", 1], ["monad", 2]
    ])
  end

  it "keeps the non-dataset eval in the same set working, with no case_id" do
    run.execute

    results = run.results["Raif::Evals::DatasetExampleEvalSet"]
    plain = results.reject { |result| result[:case_id] }

    expect(plain.count).to eq(2)
    expect(plain.map { |result| result[:description] }.uniq).to eq(["runs without a dataset"])
    expect(plain.first).not_to have_key(:case_id)
  end

  it "reports a pass rate per case" do
    run.execute

    row = run.send(:summary_data)[:eval_pass_rates].find { |r| r[:description] == "mentions the topic it was given" }

    expect(row).to include(cases: 3, repeats: 2, runs: 6, passed: 2, pass_rate: 0.3333)
    expect(row[:per_case]).to eq([
      { case_id: "chicken", runs: 2, errored: 0, passed: 2, pass_rate: 1.0 },
      { case_id: "atom", runs: 2, errored: 0, passed: 0, pass_rate: 0.0 },
      { case_id: "monad", runs: 2, errored: 0, passed: 0, pass_rate: 0.0 }
    ])
  end

  it "aggregates scores across cases, including the judge's" do
    run.execute

    summaries = run.send(:summary_data)[:score_summaries]

    topic_length = summaries.find { |s| s[:name] == "topic_length" }
    expect(topic_length).to include(n: 6, mean: 8.0, min: 5.0, max: 12.0)
    expect(topic_length[:per_case]).to eq([
      { case_id: "chicken", n: 2, mean: 7.0 },
      { case_id: "atom", n: 2, mean: 5.0 },
      { case_id: "monad", n: 2, mean: 12.0 }
    ])

    clarity = summaries.find { |s| s[:name] == "clarity" }
    expect(clarity).to include(n: 6, mean: 5.0, stddev: 0.0, scale: "1..5", higher_is_better: true)
  end

  # stddev and ci95 are over the per-case means, not over every observation: pooling the 6 would
  # mix differences between the three topics with repeat-to-repeat noise on one topic, and report
  # how varied the dataset is where the reader needs to know how uncertain the mean is.
  # spread_n names what they were measured on, so "n 6" beside them cannot be misread as the unit.
  it "measures score spread over cases rather than over every observation" do
    run.execute

    topic_length = run.send(:summary_data)[:score_summaries].find { |s| s[:name] == "topic_length" }

    # Sample stddev of the per-case means [7.0, 5.0, 12.0], not of the 6 pooled values.
    expect(topic_length).to include(n: 6, spread_n: 3)
    expect(topic_length[:stddev]).to be_within(0.0001).of(Raif::Evals::Statistics.stddev([7.0, 5.0, 12.0]))
    expect(topic_length[:stddev]).not_to be_within(0.0001).of(Raif::Evals::Statistics.stddev([7.0, 7.0, 5.0, 5.0, 12.0, 12.0]))
  end

  # Two observations but only one case, so there is no between-case variation to report. Pooled,
  # this would have measured the two repeats of one input and called that the spread - which is the
  # unit the mean is not taken over and the interval is not resampled from.
  it "reports no spread for a one-case dataset however many times it repeated" do
    single = Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 2, cases: ["chicken"])
    single.execute

    topic_length = single.send(:summary_data)[:score_summaries].find { |s| s[:name] == "topic_length" }

    expect(topic_length).to include(n: 2, spread_n: 1)
    expect(topic_length).not_to have_key(:stddev)
    expect(topic_length).not_to have_key(:ci95)
  end

  # A single-case run at --repeat 1 measures no spread, and "sd 0.0, ci95 [5.0, 5.0]" would
  # report one anyway.
  it "omits stddev and ci95 from a score summary built from one observation" do
    single = Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 1, cases: ["chicken"])
    single.execute

    clarity = single.send(:summary_data)[:score_summaries].find { |s| s[:name] == "clarity" }

    expect(clarity).to include(n: 1, mean: 5.0)
    expect(clarity).not_to have_key(:stddev)
    expect(clarity).not_to have_key(:ci95)
  end

  # A percentile bootstrap over 3 case means restates those three rather than inferring from them,
  # and would carry a "95%" label while doing it. Naming the reason is what tells a reader the fix
  # is more cases rather than a missing feature.
  it "omits ci95 below the minimum sample and says why" do
    run.execute

    topic_length = run.send(:summary_data)[:score_summaries].find { |s| s[:name] == "topic_length" }

    expect(topic_length).to include(spread_n: 3, ci95_omitted: "3 cases; a 95% interval needs 5")
    expect(topic_length).not_to have_key(:ci95)
    expect(output.string).to include("ci95 omitted: 3 cases; a 95% interval needs 5")
  end

  # Without this an edited case reads as a model regression: evals:compare joins on case id, so the
  # same id carrying a different input is reported as the model behaving differently on one input.
  it "records what each dataset held in the results configuration" do
    run.execute

    json_file = Rails.root.join("raif_evals", "results", "eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json")
    payload = JSON.parse(File.read(json_file))
    rows = File.readlines(Rails.root.join("raif_evals", "datasets", "topics.jsonl")).map { |line| JSON.parse(line) }

    expect(payload["configuration"]["datasets"]).to eq([{
      "eval_set" => "Raif::Evals::DatasetExampleEvalSet",
      "name" => "topics",
      "cases" => 3,
      "digest" => Raif::Evals::Dataset.new(name: :topics, cases: rows).digest
    }])
  end

  it "records how many cases a selection narrowed each dataset to" do
    narrowed = Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: StringIO.new, repeats: 1, cases: ["monad"])
    narrowed.execute

    expect(narrowed.send(:configuration_data)[:datasets].first).to include(cases: 3, selected: 1)
  end

  # The judge is the same on both sides of a comparison by design, so a cost row that is really the
  # judge reading a wordier model must not read as the model costing more.
  it "reports the judge's share of the run's LLM usage apart from the model under test's" do
    run.execute

    summary = run.send(:summary_data)

    expect(summary[:total_model_completions]).to eq(12)
    expect(summary[:total_judge_model_completions]).to eq(6)
    expect(summary).to include(:total_judge_tokens, :total_judge_cost)
    expect(output.string).to include("model under test")
    expect(output.string).to include("judge (6 calls)")
  end

  it "prints one compact line per case per repeat, with the failing expectations beneath" do
    run.execute

    plain_output = output.string.gsub(/\e\[\d+m/, "")

    expect(plain_output).to include("mentions the topic it was given")
    expect(plain_output).to include("✓ chicken  run 1  4/4 expectations  topic_length 7  clarity 5")
    expect(plain_output).to include("✗ atom     run 1  3/4 expectations  topic_length 5  clarity 5")
    expect(plain_output).to include("✗ response mentions the subject")
  end

  it "exports case ids and scores to the results JSON" do
    run.execute

    json_file = Rails.root.join("raif_evals", "results", "eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json")
    payload = JSON.parse(File.read(json_file))
    result = payload["results"]["Raif::Evals::DatasetExampleEvalSet"].first

    expect(result["case_id"]).to eq("chicken")
    expect(result["scores"]).to eq([
      { "name" => "topic_length", "value" => 7.0, "higher_is_better" => true },
      { "name" => "clarity", "value" => 5.0, "scale" => "1..5", "higher_is_better" => true, "min" => 4, "passed" => true }
    ])
    expect(payload["summary"]["eval_pass_rates"].first).to have_key("per_case")
    expect(payload["summary"]["score_summaries"]).to be_present
  end

  context "with --cases" do
    let(:run) do
      Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 1, cases: ["monad"])
    end

    it "runs only the named cases" do
      run.execute

      results = run.results["Raif::Evals::DatasetExampleEvalSet"]
      expect(results.filter_map { |result| result[:case_id] }).to eq(["monad"])
    end

    # The non-dataset eval in the same set runs regardless, so a typo has to be caught on the
    # case ids rather than on the result count.
    it "exits non-zero when the selection matched no case anywhere" do
      typo_run = Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 1, cases: ["monda"])

      expect { typo_run.execute }.to raise_error(SystemExit)
      expect(output.string).to include("No eval cases matched --cases monda")
    end

    # Those same non-dataset evals already spent inference money by the time the typo is caught,
    # so exiting must not also throw away the results file describing what they did.
    it "still exports results and prints a summary before exiting" do
      typo_run = Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 1, cases: ["monda"])

      expect { typo_run.execute }.to raise_error(SystemExit)

      json_file = Rails.root.join("raif_evals", "results", "eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json")
      expect(File).to exist(json_file)
      expect(JSON.parse(File.read(json_file))["results"]["Raif::Evals::DatasetExampleEvalSet"]).to be_present
      expect(output.string).to include("SUMMARY")
    end
  end

  context "with --sample and --seed" do
    let(:run) do
      Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 1, sample: 2, seed: 42)
    end

    it "runs a reproducible subset, recorded in the results configuration" do
      run.execute
      first_selection = run.results["Raif::Evals::DatasetExampleEvalSet"].filter_map { |result| result[:case_id] }

      expect(first_selection.count).to eq(2)

      second_run = Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: StringIO.new, repeats: 1, sample: 2, seed: 42)
      second_run.execute

      expect(second_run.results["Raif::Evals::DatasetExampleEvalSet"].filter_map { |result| result[:case_id] }).to eq(first_selection)
      expect(second_run.send(:configuration_data)).to include(sample: 2, seed: 42)
    end
  end

  context "with --sample and no --seed" do
    let(:results_dir) { Rails.root.join("raif_evals", "results") }
    let(:log_path) { results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.partial.jsonl") }
    let(:run) { Raif::Evals::Run.new(file_paths: [{ file_path: eval_set_path }], output: output, repeats: 1, sample: 2) }

    after { FileUtils.rm_f(log_path) }

    it "draws a seed of its own and reports it" do
      run.execute

      expect(run.seed).to be_a(Integer)
      expect(run.send(:configuration_data)).to include(sample: 2, seed: run.seed)
      expect(output.string).to include("Sample per dataset: 2 (seed #{run.seed})")
    end

    it "adopts the seed the log records rather than drawing a new one" do
      # Stands in for the first attempt, with a seed the assertions below can name. What it
      # drew for itself is beside the point; what matters is that the resume reuses it.
      interrupted = Raif::Evals::Run.new(
        file_paths: [{ file_path: eval_set_path }], output: StringIO.new, repeats: 1, sample: 2, seed: 42
      )
      interrupted.execute
      selection = interrupted.results["Raif::Evals::DatasetExampleEvalSet"].filter_map { |result| result[:case_id] }

      expect(selection.count).to eq(2)

      # The log it would have left behind had it died partway, carrying the seed it sampled on.
      log = Raif::Evals::RunLog.start(
        results_dir: results_dir,
        basename: "eval_run_20240101_120000_#{Raif.config.default_llm_model_key}",
        run_at: Time.current.iso8601,
        configuration: interrupted.send(:configuration_data)
      )

      resumed = Raif::Evals::Run.new(
        file_paths: [{ file_path: eval_set_path }],
        output: StringIO.new,
        repeats: 1,
        sample: 2,
        resume_path: log.path.to_s
      )

      # Drawing a fresh seed here would both resample the dataset and be refused outright, since
      # the new seed no longer matches the one the log was started with.
      expect(resumed.seed).to eq(42)

      resumed.execute

      expect(resumed.results["Raif::Evals::DatasetExampleEvalSet"].filter_map { |result| result[:case_id] }).to eq(selection)
    end
  end

  context "when capture is limited to :summary" do
    before { allow(Raif.config).to receive(:evals_capture_model_completions).and_return(:summary) }

    it "keeps tokens and cost but drops the prompt and response text" do
      run.execute

      result = run.results["Raif::Evals::DatasetExampleEvalSet"].first
      completion = result[:model_completions].first

      expect(completion).to include(:llm_model_key, :total_tokens)
      expect(completion).not_to include(:system_prompt, :messages, :response)
      expect(result[:usage][:model_completions]).to eq(2)
    end
  end

  context "when capture is disabled" do
    before { allow(Raif.config).to receive(:evals_capture_model_completions).and_return(:none) }

    it "omits the completions array but still reports usage" do
      run.execute

      result = run.results["Raif::Evals::DatasetExampleEvalSet"].first

      expect(result).not_to have_key(:model_completions)
      expect(result[:usage][:model_completions]).to eq(2)
    end
  end
end
