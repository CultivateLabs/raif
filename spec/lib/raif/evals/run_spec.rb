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
    it "accepts specific eval sets by name" do
      allow_any_instance_of(described_class).to receive(:discover_eval_sets).and_return([TestEvalSet, AnotherEvalSet])
      run = described_class.new(eval_sets: ["TestEvalSet"])
      expect(run.eval_sets.map(&:name)).to eq(["TestEvalSet"])

      run = described_class.new(eval_sets: ["TestEvalSet", "AnotherEvalSet"])
      expect(run.eval_sets.map(&:name)).to eq(["TestEvalSet", "AnotherEvalSet"])
    end

    context "with auto-discovery" do
      let(:eval_sets_dir) { Rails.root.join("raif_evals", "eval_sets") }

      before do
        FileUtils.mkdir_p eval_sets_dir
      end

      it "discovers eval set files" do
        discovered_file = eval_sets_dir.join("discovered_eval_set.rb")
        File.write(discovered_file, <<~RUBY)
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
      ensure
        FileUtils.rm(discovered_file) if File.exist?(discovered_file)
      end

      it "handles namespaced eval sets" do
        namespace_dir = eval_sets_dir.join("my_module")
        FileUtils.mkdir_p(namespace_dir)
        namespaced_file = namespace_dir.join("namespaced_eval_set.rb")

        File.write(namespaced_file, <<~RUBY)
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
      expect(TestEvalSet).to receive(:run).with(output: output).and_call_original
      expect(AnotherEvalSet).to receive(:run).with(output: output).and_call_original

      run.execute
    end

    context "when running specific eval sets by name" do
      it "runs only the specified eval set when given a single name" do
        run = described_class.new(eval_sets: ["TestEvalSet"], output: output)

        expect(TestEvalSet).to receive(:run).with(output: output).and_call_original
        expect(AnotherEvalSet).not_to receive(:run)

        run.execute

        expect(run.results.keys).to eq(["TestEvalSet"])
      end

      it "runs multiple specified eval sets when given multiple names" do
        run = described_class.new(eval_sets: ["TestEvalSet", "AnotherEvalSet"], output: output)

        expect(TestEvalSet).to receive(:run).with(output: output).and_call_original
        expect(AnotherEvalSet).to receive(:run).with(output: output).and_call_original

        run.execute

        expect(run.results.keys).to contain_exactly("TestEvalSet", "AnotherEvalSet")
      end

      it "handles non-existent eval set names gracefully" do
        run = described_class.new(eval_sets: ["NonExistentEvalSet", "TestEvalSet"], output: output)

        expect(TestEvalSet).to receive(:run).with(output: output).and_call_original
        expect(AnotherEvalSet).not_to receive(:run)

        run.execute

        expect(run.results.keys).to eq(["TestEvalSet"])
      end

      it "runs no eval sets when only non-existent names are provided" do
        run = described_class.new(eval_sets: ["NonExistentEvalSet"], output: output)

        expect(TestEvalSet).not_to receive(:run)
        expect(AnotherEvalSet).not_to receive(:run)

        run.execute

        expect(run.results).to be_empty
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
    ensure
      FileUtils.rm(json_file)
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
    end
  end
end
