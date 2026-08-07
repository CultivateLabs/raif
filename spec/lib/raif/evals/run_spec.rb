# frozen_string_literal: true

require "rails_helper"
require "fileutils"

RSpec.describe Raif::Evals::Run do
  let(:test_eval_set) do
    Class.new(Raif::Evals::EvalSet) do
      eval "passes" do
        expect "always true" do
          true
        end
      end

      eval "fails" do
        expect "always false" do
          false
        end
      end
    end
  end

  let(:another_eval_set) do
    Class.new(Raif::Evals::EvalSet) do
      eval "another test" do
        expect "also passes" do
          true
        end
      end
    end
  end

  before do
    stub_const("TestEvalSet", test_eval_set)
    stub_const("AnotherEvalSet", another_eval_set)
  end

  describe "#initialize" do
    context "with file specs" do
      let(:temp_eval_file) { Rails.root.join("tmp", "test_eval_set.rb") }
      let(:another_temp_eval_file) { Rails.root.join("tmp", "another", "eval_set.rb") }

      before do
        FileUtils.mkdir_p Rails.root.join("tmp", "another")
        File.write(temp_eval_file, <<~RUBY)
          class TestEvalSetFromFile < Raif::Evals::EvalSet
            eval "test from file" do
              expect "passes" do
                true
              end
            end
          end
        RUBY

        File.write(another_temp_eval_file, <<~RUBY)
          module Another
            class EvalSetFromFile < Raif::Evals::EvalSet
              eval "another test from file" do
                expect "also passes" do
                  true
                end
              end
            end
          end
        RUBY
      end

      after do
        FileUtils.rm(temp_eval_file) if File.exist?(temp_eval_file)
        FileUtils.rm(another_temp_eval_file) if File.exist?(another_temp_eval_file)
      end

      it "includes line numbers when specified" do
        run = described_class.new(file_paths: [{ file_path: temp_eval_file.to_s, line_number: 10 }])
        expect(run.eval_sets.first[:line_number]).to eq(10)
      end
    end

    context "with auto-discovery" do
      let(:eval_sets_dir) { Rails.root.join("raif_evals", "eval_sets") }

      before do
        FileUtils.mkdir_p eval_sets_dir
      end

      it "discovers eval set files" do
        discovered_file = eval_sets_dir.join("discovered_eval_set.rb")
        File.write(discovered_file, <<~RUBY)
          class Raif::Evals::DiscoveredEvalSet < Raif::Evals::EvalSet
            eval "discovered" do
              expect "found" do
                true
              end
            end
          end
        RUBY

        run = described_class.new
        expect(run.eval_sets.map(&:name)).to include("Raif::Evals::DiscoveredEvalSet")
      ensure
        FileUtils.rm(discovered_file) if File.exist?(discovered_file)
      end

      it "handles namespaced eval sets" do
        namespace_dir = eval_sets_dir.join("my_module")
        FileUtils.mkdir_p(namespace_dir)
        namespaced_file = namespace_dir.join("namespaced_eval_set.rb")

        File.write(namespaced_file, <<~RUBY)
          module Raif
            module Evals
              module MyModule
                class NamespacedEvalSet < Raif::Evals::EvalSet
                  eval "namespaced" do
                    expect "works" do
                      true
                    end
                  end
                end
              end
            end
          end
        RUBY

        run = described_class.new
        expect(run.eval_sets.map(&:name)).to include("Raif::Evals::MyModule::NamespacedEvalSet")
      ensure
        FileUtils.rm(namespaced_file)
        FileUtils.rmdir(namespace_dir) if Dir.exist?(namespace_dir) && Dir.empty?(namespace_dir)
      end
    end
  end

  describe "#execute" do
    let(:output) { StringIO.new }
    let(:run) { described_class.new(output: output) }

    before do
      allow(Time).to receive(:current).and_return(Time.new(2024, 1, 1, 12, 0, 0))
      allow_any_instance_of(described_class).to receive(:discover_eval_sets).and_return([TestEvalSet, AnotherEvalSet])
    end

    it "runs all eval sets" do
      expect(TestEvalSet).to receive(:run)
        .with(hash_including(output: output, repeats: 1, cases: nil, sample: nil, seed: nil)).and_call_original
      expect(AnotherEvalSet).to receive(:run)
        .with(hash_including(output: output, repeats: 1, cases: nil, sample: nil, seed: nil)).and_call_original

      run.execute
    end

    context "when running specific eval sets from files" do
      let(:temp_eval_file) { Rails.root.join("tmp", "test_eval_for_execute.rb") }
      let(:another_temp_eval_file) { Rails.root.join("tmp", "another_eval_for_execute.rb") }

      before do
        FileUtils.mkdir_p Rails.root.join("tmp")
        File.write(temp_eval_file, <<~RUBY)
          class TestEvalForExecute < Raif::Evals::EvalSet
            eval "first test" do
              expect "passes" do
                true
              end
            end
          #{"  "}
            eval "second test" do
              expect "also passes" do
                true
              end
            end
          end
        RUBY

        File.write(another_temp_eval_file, <<~RUBY)
          class AnotherEvalForExecute < Raif::Evals::EvalSet
            eval "another test" do
              expect "passes too" do
                true
              end
            end
          end
        RUBY
      end

      after do
        FileUtils.rm(temp_eval_file) if File.exist?(temp_eval_file)
        FileUtils.rm(another_temp_eval_file) if File.exist?(another_temp_eval_file)
      end

      it "runs only the specified eval set when given a single file" do
        run = described_class.new(file_paths: [{ file_path: temp_eval_file.to_s }], output: output)
        run.execute

        expect(run.results.keys).to eq(["TestEvalForExecute"])
        expect(run.results["TestEvalForExecute"].size).to eq(2)
      end

      it "handles non-existent file paths with error" do
        expect do
          described_class.new(file_paths: [{ file_path: "/non/existent/file.rb" }], output: output)
        end.to raise_error(SystemExit)
      end
    end

    it "collects results from all eval sets" do
      run.execute

      expect(run.results.keys).to contain_exactly("TestEvalSet", "AnotherEvalSet")
      expect(run.results["TestEvalSet"].size).to eq(2)
      expect(run.results["AnotherEvalSet"].size).to eq(1)
    end

    it "exports results to JSON file" do
      results_dir = Rails.root.join("raif_evals", "results")

      run.execute

      json_file = results_dir.join("eval_run_20240101_120000_#{Raif.config.default_llm_model_key}.json")
      expect(File.exist?(json_file)).to be true

      json_content = JSON.parse(File.read(json_file))
      expect(Time.parse(json_content["run_at"])).to eq(Time.new(2024, 1, 1, 12, 0, 0))
      expect(json_content["results"]).to be_a(Hash)
      expect(json_content["configuration"]).to eq(
        "default_llm_model_key" => Raif.config.default_llm_model_key.to_s,
        "evals_default_llm_judge_model_key" => Raif.config.evals_default_llm_judge_model_key,
        "repeats" => 1,
        "capture_model_completions" => "full",
        "cases" => nil,
        "sample" => nil,
        "seed" => nil
      )
      expect(json_content["summary"]).to include(
        "total_eval_sets" => 2,
        "total_evals" => 3,
        "passed_evals" => 2,
        "total_model_completions" => 0,
        "total_prompt_tokens" => 0,
        "total_completion_tokens" => 0,
        "total_tokens" => 0,
        "total_cost" => 0.0
      )
    ensure
      FileUtils.rm(json_file)
    end

    context "with repeats" do
      let(:run) { described_class.new(output: output, repeats: 3) }

      it "runs each eval once per repeat and tags them with a run index" do
        run.execute

        expect(run.results["TestEvalSet"].size).to eq(6)
        expect(run.results["AnotherEvalSet"].size).to eq(3)

        indexes = run.results["AnotherEvalSet"].map { |e| e[:run_index] }
        expect(indexes).to eq([1, 2, 3])
      end

      it "collapses the repeats into a per-eval pass rate" do
        run.execute

        rates = run.send(:summary_data)[:eval_pass_rates]

        expect(rates).to include(
          { eval_set: "TestEvalSet", description: "passes", runs: 3, passed: 3, pass_rate: 1.0 },
          { eval_set: "TestEvalSet", description: "fails", runs: 3, passed: 0, pass_rate: 0.0 },
          { eval_set: "AnotherEvalSet", description: "another test", runs: 3, passed: 3, pass_rate: 1.0 }
        )
      end

      # The DSL does not enforce unique descriptions, and grouping by description would
      # report one blended row of 6 runs instead of one row per eval block.
      context "when two eval blocks share a description" do
        let(:test_eval_set) do
          Class.new(Raif::Evals::EvalSet) do
            eval "same name" do
              expect("always true") { true }
            end

            eval "same name" do
              expect("always false") { false }
            end
          end
        end

        it "keeps them as separate rows" do
          run.execute

          rates = run.send(:summary_data)[:eval_pass_rates].select { |r| r[:eval_set] == "TestEvalSet" }

          expect(rates.size).to eq(2)
          expect(rates).to contain_exactly(
            { eval_set: "TestEvalSet", description: "same name", runs: 3, passed: 3, pass_rate: 1.0 },
            { eval_set: "TestEvalSet", description: "same name", runs: 3, passed: 0, pass_rate: 0.0 }
          )
        end
      end
    end

    it "omits the run index when each eval runs only once" do
      run.execute

      expect(run.results["AnotherEvalSet"].first).not_to have_key(:run_index)
    end

    it "includes usage and captured model completions for each eval in the results" do
      run.execute

      eval_result = run.results["TestEvalSet"].first
      expect(eval_result).to include(:usage, :model_completions)
      expect(eval_result[:usage]).to include(
        model_completions: 0,
        total_tokens: 0,
        total_cost: 0.0
      )
      expect(eval_result[:model_completions]).to eq([])
    end

    it "prints summary to output" do
      run.execute

      output_string = output.string
      expect(output_string).to include("Starting Raif Eval Run")
      expect(output_string).to include("Running TestEvalSet")
      expect(output_string).to include("Running AnotherEvalSet")
      expect(output_string).to include("SUMMARY")
      expect(output_string).to include("Eval Sets: 2")
      expect(output_string).to include("Evals:")
      expect(output_string).to include("  3 total")
      expect(output_string).to include("  2 passed")
      expect(output_string).to include("  1 failed")
      expect(output_string).to include("Expectations:")
      expect(output_string).to include("  3 total")
      expect(output_string).to include("  2 passed")
      expect(output_string).to include("  1 failed")
      expect(output_string).to include("LLM Usage:")
      expect(output_string).to include("0 LLM calls")
      expect(output_string).to include("0 total tokens")
      expect(output_string).to include("$0.000000 total cost")
    end
  end

  describe "the --cases no-match guard" do
    # A set can declare a dataset that no eval actually consumes. Running only its plain evals
    # under --cases must not be mistaken for a filter that matched nothing.
    let(:declares_unused_dataset) do
      Class.new(Raif::Evals::EvalSet) do
        dataset :topics do
          [{ id: "a", input: {} }]
        end

        eval "runs without the dataset" do
          expect("passes") { true }
        end
      end
    end

    it "does not fire when no eval in the run uses a dataset" do
      run = described_class.new(file_paths: [], output: output, repeats: 1, cases: ["a"])
      run.instance_variable_set(:@eval_sets, [{ class: declares_unused_dataset }])

      expect(run.send(:dataset_evals_present?)).to be false
    end

    it "fires when an eval in the run uses a dataset" do
      uses_dataset = Class.new(Raif::Evals::EvalSet) do
        dataset(:topics) { [{ id: "a", input: {} }] }
        eval("over the dataset", dataset: :topics) { expect("passes") { true } }
      end

      run = described_class.new(file_paths: [], output: output, repeats: 1, cases: ["a"])
      run.instance_variable_set(:@eval_sets, [{ class: uses_dataset }])

      expect(run.send(:dataset_evals_present?)).to be true
    end
  end

  describe "per-case score means" do
    # The bootstrap CI resamples per-case means, so those must stay unrounded even though
    # score_per_case rounds the same means for display.
    it "are unrounded, unlike the values score_per_case reports" do
      run = described_class.new(file_paths: [], output: output, repeats: 1)
      scores = [
        { case_id: "a", name: "clarity", value: 1.0 },
        { case_id: "a", name: "clarity", value: 2.0 },
        { case_id: "a", name: "clarity", value: 2.0 }
      ]

      expect(run.send(:per_case_means, scores)).to eq([5.0 / 3])
      expect(run.send(:score_per_case, scores).first[:mean]).to eq(1.6667)
    end
  end
end
