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
    it "accepts specific eval sets" do
      run = described_class.new(eval_sets: [TestEvalSet])
      expect(run.eval_sets).to eq([TestEvalSet])
    end

    context "with auto-discovery" do
      let(:eval_sets_dir) { Rails.root.join("raif_evals", "eval_sets") }

      before do
        FileUtils.mkdir_p(eval_sets_dir)
      end

      after do
        FileUtils.rm_rf(Rails.root.join("raif_evals"))
      end

      it "discovers eval set files" do
        File.write(eval_sets_dir.join("discovered_eval_set.rb"), <<~RUBY)
          class DiscoveredEvalSet < Raif::Evals::EvalSet
            eval "discovered" do
              expect "found" do
                true
              end
            end
          end
        RUBY

        run = described_class.new
        expect(run.eval_sets.map(&:name)).to include("DiscoveredEvalSet")
      end

      it "handles namespaced eval sets" do
        namespace_dir = eval_sets_dir.join("my_module")
        FileUtils.mkdir_p(namespace_dir)

        File.write(namespace_dir.join("namespaced_eval_set.rb"), <<~RUBY)
          module MyModule
            class NamespacedEvalSet < Raif::Evals::EvalSet
              eval "namespaced" do
                expect "works" do
                  true
                end
              end
            end
          end
        RUBY

        run = described_class.new
        expect(run.eval_sets.map(&:name)).to include("MyModule::NamespacedEvalSet")
      end
    end
  end

  describe "#execute" do
    let(:output) { StringIO.new }
    let(:run) { described_class.new(eval_sets: [TestEvalSet, AnotherEvalSet], output: output) }

    before do
      allow(Time).to receive(:current).and_return(Time.new(2024, 1, 1, 12, 0, 0))
    end

    it "runs all eval sets" do
      expect(TestEvalSet).to receive(:run).with(output: output).and_call_original
      expect(AnotherEvalSet).to receive(:run).with(output: output).and_call_original

      run.execute
    end

    it "collects results from all eval sets" do
      run.execute

      expect(run.results.keys).to contain_exactly("TestEvalSet", "AnotherEvalSet")
      expect(run.results["TestEvalSet"].size).to eq(2)
      expect(run.results["AnotherEvalSet"].size).to eq(1)
    end

    it "exports results to JSON file" do
      results_dir = Rails.root.join("raif_evals", "results")
      FileUtils.mkdir_p(results_dir)

      run.execute

      json_file = results_dir.join("eval_run_20240101_120000.json")
      expect(File.exist?(json_file)).to be true

      json_content = JSON.parse(File.read(json_file))
      expect(Time.parse(json_content["run_at"])).to eq(Time.new(2024, 1, 1, 12, 0, 0))
      expect(json_content["results"]).to be_a(Hash)
      expect(json_content["summary"]).to include(
        "total_eval_sets" => 2,
        "total_evals" => 3,
        "passed_evals" => 2
      )

      FileUtils.rm_rf(Rails.root.join("raif_evals"))
    end

    it "prints summary to output" do
      run.execute

      output_string = output.string
      expect(output_string).to include("Starting Raif Eval Run")
      expect(output_string).to include("Running TestEvalSet")
      expect(output_string).to include("Running AnotherEvalSet")
      expect(output_string).to include("SUMMARY")
      expect(output_string).to include("Eval Sets: 2")
      expect(output_string).to include("Evals: 2/3 passed")
    end
  end
end
