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
      { case_id: "chicken", runs: 2, passed: 2, pass_rate: 1.0 },
      { case_id: "atom", runs: 2, passed: 0, pass_rate: 0.0 },
      { case_id: "monad", runs: 2, passed: 0, pass_rate: 0.0 }
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
