# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::EvalSet do
  let(:test_eval_set_class) do
    Class.new(described_class) do
      setup do
        @setup_called = true
      end

      teardown do
        @teardown_called = true
      end

      eval "test passes" do
        expect "always passes" do
          true
        end
      end

      eval "test fails" do
        expect "always fails" do
          false
        end
      end

      eval "test with multiple expectations" do
        expect "first passes" do
          true
        end

        expect "second fails" do
          false
        end

        expect "third passes" do
          true
        end
      end
    end
  end

  describe ".eval" do
    it "adds eval definitions to the class" do
      expect(test_eval_set_class.evals.size).to eq(3)
      expect(test_eval_set_class.evals.first[:description]).to eq("test passes")
    end

    it "raises when called without a block" do
      expect do
        Class.new(described_class) do
          eval "no block given"
        end
      end.to raise_error(ArgumentError, /requires a block/)
    end

    it "does not register the eval when called without a block" do
      eval_set_class = Class.new(described_class)

      expect { eval_set_class.eval("no block given") }.to raise_error(ArgumentError)
      expect(eval_set_class.evals).to be_empty
    end
  end

  describe ".dataset" do
    it "raises when called without a block" do
      expect do
        Class.new(described_class) do
          dataset :topics
        end
      end.to raise_error(ArgumentError, /requires a block/)
    end

    # A typo'd dataset name would otherwise run zero cases and report a suite that passed.
    it "raises when an eval names a dataset that was not declared" do
      expect do
        Class.new(described_class) do
          dataset(:topics) { [] }

          eval "uses a typo", dataset: :topcis do
            expect("never runs") { true }
          end
        end
      end.to raise_error(ArgumentError, /names dataset :topcis, which has not been declared/)
    end

    it "raises when given an inline array instead of a registered name" do
      expect do
        Class.new(described_class) do
          eval "inlines its cases", dataset: [{ id: "alpha", input: {} }] do
            expect("never runs") { true }
          end
        end
      end.to raise_error(ArgumentError, /passed Array to dataset:/)
    end

    it "raises when no datasets have been declared at all" do
      expect do
        Class.new(described_class) do
          eval "uses a dataset", dataset: :topics do
            expect("never runs") { true }
          end
        end
      end.to raise_error(ArgumentError, /has not been declared/)
    end
  end

  describe ".run with a dataset" do
    let(:dataset_eval_set) do
      Class.new(described_class) do
        dataset :topics do
          [
            { id: "alpha", input: { "n" => 1 }, expected: { "double" => 2 } },
            { id: "beta", input: { "n" => 2 }, expected: { "double" => 4 } }
          ]
        end

        setup do |eval_case|
          @doubled = eval_case["n"] * 2
        end

        eval "doubles the input", dataset: :topics do |eval_case|
          expect "setup ran for this case" do
            @doubled == eval_case.expected["double"]
          end

          score "n", eval_case["n"]
        end
      end
    end

    it "runs the eval body once per case per repeat, stamping each result with its case" do
      results = dataset_eval_set.run(output: StringIO.new, repeats: 2)

      expect(results.map { |result| [result.case_id, result.run_index] }).to eq([
        ["alpha", 1], ["alpha", 2], ["beta", 1], ["beta", 2]
      ])
      expect(results).to all(be_passed)
    end

    it "records scores on each result" do
      results = dataset_eval_set.run(output: StringIO.new)

      expect(results.map { |result| result.scores.map(&:value) }).to eq([[1.0], [2.0]])
    end

    it "restricts the run to the selected cases" do
      results = dataset_eval_set.run(output: StringIO.new, cases: ["beta"])

      expect(results.map(&:case_id)).to eq(["beta"])
    end

    it "skips the eval entirely when the selection matches none of its cases" do
      expect(dataset_eval_set.run(output: StringIO.new, cases: ["nope"])).to eq([])
    end

    # One bad fixture in a 20-case dataset must not cost the other 19 results.
    it "records an error for a case that raises and keeps running the rest" do
      eval_set = Class.new(described_class) do
        dataset :topics do
          [{ id: "alpha", input: { "n" => 1 } }, { id: "beta", input: { "n" => 2 } }]
        end

        eval "blows up on alpha", dataset: :topics do |eval_case|
          raise "boom" if eval_case.id == "alpha"

          expect("beta is fine") { true }
        end
      end

      results = eval_set.run(output: StringIO.new)

      expect(results.map(&:case_id)).to eq(["alpha", "beta"])
      expect(results.first.expectation_results.first).to be_error
      expect(results.second).to be_passed
    end

    it "records an error for a case whose setup raises and keeps running the rest" do
      eval_set = Class.new(described_class) do
        dataset :topics do
          [{ id: "alpha", input: { "n" => 1 } }, { id: "beta", input: { "n" => 2 } }]
        end

        setup do |eval_case|
          raise "bad fixture" if eval_case.id == "alpha"
        end

        eval "runs for both cases", dataset: :topics do
          expect("ran") { true }
        end
      end

      results = eval_set.run(output: StringIO.new)

      expect(results.map(&:case_id)).to eq(["alpha", "beta"])
      expect(results.first.expectation_results.map(&:description)).to eq(["Setup execution"])
      expect(results.first.expectation_results.first).to be_error
      expect(results.second).to be_passed
    end

    it "raises before running anything when the dataset has duplicate ids" do
      eval_set = Class.new(described_class) do
        dataset :topics do
          [{ id: "alpha", input: {} }, { id: "alpha", input: {} }]
        end

        eval "never runs", dataset: :topics do
          raise "should not get here"
        end
      end

      expect { eval_set.run(output: StringIO.new) }.to raise_error(ArgumentError, /duplicate case ids/)
    end
  end

  describe ".run" do
    it "executes all evals and returns results" do
      output = StringIO.new
      results = test_eval_set_class.run(output: output)

      expect(results.size).to eq(3)
      expect(results[0].description).to eq("test passes")
      expect(results[0].passed?).to be true
      expect(results[1].description).to eq("test fails")
      expect(results[1].passed?).to be false
      expect(results[2].description).to eq("test with multiple expectations")
      expect(results[2].passed?).to be false
    end

    # The backwards-compatibility guarantee: adding datasets to the DSL must not require
    # touching an eval set that does not use them.
    it "leaves zero-arity setup, teardown, and eval blocks running exactly as before" do
      eval_set = Class.new(described_class) do
        setup do
          @calls = ["setup"]
        end

        teardown do
          @calls << "teardown"
        end

        eval "no case" do
          expect("setup ran with no argument") { @calls == ["setup"] }
        end
      end

      results = eval_set.run(output: StringIO.new)

      expect(results.first).to be_passed
      expect(results.first.case_id).to be_nil
      expect(results.first.to_h).not_to have_key(:case_id)
    end

    it "runs within a transaction that is rolled back" do
      eval_set_with_db = Class.new(described_class) do
        eval "creates a record" do
          initial_count = Raif::Conversation.count
          user = FB.create(:raif_test_user)
          Raif::Conversation.create!(type: "Raif::Conversation", creator: user)

          expect "record was created" do
            Raif::Conversation.count == initial_count + 1
          end
        end
      end

      initial_count = Raif::Conversation.count
      eval_set_with_db.run
      expect(Raif::Conversation.count).to eq(initial_count)
    end

    it "captures model completions created during the eval before the transaction rolls back" do
      eval_set_with_llm_call = Class.new(described_class) do
        eval "makes an LLM call" do
          FB.create(
            :raif_model_completion,
            llm_model_key: "raif_test_llm",
            model_api_name: "raif-test-llm",
            prompt_tokens: 30,
            completion_tokens: 12,
            total_tokens: 42
          )

          expect "ran" do
            true
          end
        end
      end

      results = eval_set_with_llm_call.run
      eval_result = results.first

      expect(eval_result.model_completions.size).to eq(1)
      expect(eval_result.model_completions.first[:llm_model_key]).to eq("raif_test_llm")
      expect(eval_result.usage).to include(
        model_completions: 1,
        prompt_tokens: 30,
        completion_tokens: 12,
        total_tokens: 42
      )
    end

    it "captures model completions before a teardown that destroys their source" do
      eval_set_with_destructive_teardown = Class.new(described_class) do
        teardown do
          @entry&.destroy
        end

        eval "makes an LLM call whose source is destroyed in teardown" do
          creator = FB.create(:raif_test_user)
          conversation = FB.create(:raif_conversation, creator: creator)
          @entry = FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator)
          FB.create(
            :raif_model_completion,
            source: @entry,
            llm_model_key: "raif_test_llm",
            model_api_name: "raif-test-llm",
            prompt_tokens: 15,
            completion_tokens: 5,
            total_tokens: 20
          )

          expect "ran" do
            true
          end
        end
      end

      results = eval_set_with_destructive_teardown.run
      eval_result = results.first

      expect(eval_result.model_completions.size).to eq(1)
      expect(eval_result.usage[:total_tokens]).to eq(20)
    end

    it "does not capture model completions created before the eval ran (setup)" do
      completion_before = FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm"
      )

      eval_set_class = Class.new(described_class) do
        eval "no LLM calls of its own" do
          expect "ran" do
            true
          end
        end
      end

      results = eval_set_class.run
      captured_keys = results.first.model_completions
      expect(captured_keys).to be_empty
      expect(Raif::ModelCompletion.exists?(completion_before.id)).to be true
    end
  end

  describe "#expect" do
    it "creates passing expectation results" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))

      instance.expect "this passes" do
        true
      end

      eval = instance.current_eval_result
      expect(eval.expectation_results.size).to eq(1)
      expect(eval.expectation_results.first.passed?).to be true
      expect(output.string).to include("✓ this passes")
    end

    it "creates failing expectation results" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))

      instance.expect "this fails" do
        false
      end

      eval = instance.current_eval_result
      expect(eval.expectation_results.size).to eq(1)
      expect(eval.expectation_results.first.failed?).to be true
      expect(output.string).to include("✗ this fails")
    end

    it "handles errors in expectation blocks" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))

      instance.expect "this errors" do
        raise "Boom!"
      end

      eval = instance.current_eval_result
      expect(eval.expectation_results.size).to eq(1)
      expect(eval.expectation_results.first.error?).to be true
      expect(output.string).to include("✗ this errors (Error: Boom!)")
    end

    context "with metadata" do
      let(:instance) do
        output = StringIO.new
        instance = test_eval_set_class.new(output: output)
        instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))
        instance
      end

      it "stores metadata with expectation results" do
        result = instance.expect "Summary is high quality", result_metadata: { overall_score: 4, clarity_score: 5.5 } do
          true
        end

        expect(result.passed?).to be true
        expect(result.to_h[:metadata]).to eq(overall_score: 4, clarity_score: 5.5)
      end

      it "handles metadata with failing expectations" do
        result = instance.expect "Score too low", result_metadata: { score: 2, rationale: "because it's too low" } do
          false
        end

        expect(result.failed?).to be true
        expect(result.to_h[:metadata]).to eq(score: 2, rationale: "because it's too low")
      end

      it "does not include metadata key when no metadata provided" do
        result = instance.expect "No metadata" do
          true
        end

        expect(result.to_h).not_to have_key(:metadata)
      end
    end
  end

  describe "#score" do
    let(:instance) do
      instance = test_eval_set_class.new(output: StringIO.new)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))
      instance
    end

    it "records the value without affecting pass/fail" do
      instance.score "summary_word_count", 284

      expect(instance.current_eval_result.scores.map(&:to_h)).to eq([
        { name: "summary_word_count", value: 284.0, higher_is_better: true }
      ])
      expect(instance.current_eval_result.expectation_results).to be_empty
      expect(instance.current_eval_result).to be_passed
    end

    it "also gates the eval when a min is given" do
      instance.score "clarity", 3, scale: 1..5, min: 4

      expect(instance.current_eval_result.expectation_results.map(&:description)).to eq(["clarity score >= 4"])
      expect(instance.current_eval_result).not_to be_passed
    end

    it "gates on a ceiling when a max is given" do
      instance.score "elapsed_ms", 812, max: 500, higher_is_better: false

      expect(instance.current_eval_result.expectation_results.map(&:description)).to eq(["elapsed_ms score <= 500"])
      expect(instance.current_eval_result).not_to be_passed
    end

    it "gates on both bounds when both are given" do
      instance.score "summary_word_count", 284, min: 100, max: 1000

      expect(instance.current_eval_result.expectation_results.map(&:description)).to eq(["summary_word_count score >= 100 and <= 1000"])
      expect(instance.current_eval_result).to be_passed
    end

    # The name is the metric the run summary aggregates by, so two of them would be averaged
    # into one row and count values from a single response as independent samples.
    it "refuses to record the same score name twice for one eval" do
      instance.score "clarity", 4

      expect { instance.score("clarity", 2) }.to raise_error(ArgumentError, /was already recorded for this eval/)
      expect(instance.current_eval_result.scores.count).to eq(1)
    end

    it "prints the value" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))

      instance.score "clarity", 4.0

      expect(output.string).to include("clarity: 4")
    end
  end

  describe "#files" do
    let(:eval_set_instance) { test_eval_set_class.new(output: StringIO.new) }
    let(:corpora_dir) { Rails.root.join("raif_evals", "files", "corpora") }

    before do
      FileUtils.mkdir_p(corpora_dir)
      File.write(corpora_dir.join("b.json"), "{}")
      File.write(corpora_dir.join("a.json"), "{}")
      File.write(corpora_dir.join("notes.txt"), "hi")
    end

    after { FileUtils.rm_rf(corpora_dir) }

    it "returns sorted paths relative to raif_evals/files, so they compose with #file" do
      expect(eval_set_instance.files("corpora/*.json")).to eq(["corpora/a.json", "corpora/b.json"])
      expect(eval_set_instance.file(eval_set_instance.files("corpora/*.json").first)).to eq("{}")
    end

    it "returns nothing when the glob matches nothing" do
      expect(eval_set_instance.files("corpora/*.csv")).to eq([])
    end

    it "refuses to traverse out of the files directory" do
      expect { eval_set_instance.files("../../*") }.to raise_error(ArgumentError, /cannot contain '\.\.'/)
    end
  end

  describe "#jsonl and #json" do
    let(:eval_set_instance) { test_eval_set_class.new(output: StringIO.new) }
    let(:datasets_dir) { Rails.root.join("raif_evals", "datasets") }

    before do
      FileUtils.mkdir_p(datasets_dir)
      File.write(datasets_dir.join("spec_cases.jsonl"), "{\"id\":\"a\"}\n\n{\"id\":\"b\"}\n")
      File.write(datasets_dir.join("spec_cases.json"), "[{\"id\":\"a\"}]")
    end

    after do
      FileUtils.rm_f(datasets_dir.join("spec_cases.jsonl"))
      FileUtils.rm_f(datasets_dir.join("spec_cases.json"))
    end

    it "reads one case per line, skipping blanks" do
      expect(eval_set_instance.jsonl("spec_cases.jsonl")).to eq([{ "id" => "a" }, { "id" => "b" }])
    end

    it "reads a JSON array" do
      expect(eval_set_instance.json("spec_cases.json")).to eq([{ "id" => "a" }])
    end

    it "raises for a missing file" do
      expect { eval_set_instance.jsonl("nope.jsonl") }.to raise_error(ArgumentError, %r{does not exist in raif_evals/datasets/})
    end
  end

  describe "#expect_tool_invocation" do
    let(:creator) { FB.create(:raif_test_user) }
    let(:conversation) { FB.create(:raif_conversation, creator: creator) }
    let(:tool_invoker) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }
    let(:eval_set_instance) do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))
      instance
    end

    it "passes when tool is invoked" do
      FB.create(
        :raif_model_tool_invocation,
        source: tool_invoker,
        tool_type: "Raif::TestModelTool"
      )

      result = eval_set_instance.expect_tool_invocation(tool_invoker, "Raif::TestModelTool")

      expect(result.passed?).to be true
      expect(result.description).to eq("invokes Raif::TestModelTool")
    end

    it "fails when tool is not invoked" do
      eval_set_instance.expect_tool_invocation(tool_invoker, "MissingTool")

      result = eval_set_instance.current_eval_result.expectation_results.first
      expect(result.failed?).to be true
    end

    it "checks arguments when with: is provided" do
      FB.create(
        :raif_model_tool_invocation,
        source: tool_invoker,
        tool_type: "Raif::TestModelTool",
        tool_arguments: { "items" => [{ "title" => "test", "description" => "test desc" }] }
      )

      result = eval_set_instance.expect_tool_invocation(
        tool_invoker,
        "Raif::TestModelTool",
        with: { items: [{ "title" => "test", "description" => "test desc" }] }
      )

      expect(result.passed?).to be true
      expect(result.description).to eq("invokes Raif::TestModelTool with {\"items\":[{\"title\":\"test\",\"description\":\"test desc\"}]}")
    end
  end

  describe "#expect_no_tool_invocation" do
    let(:creator) { FB.create(:raif_test_user) }
    let(:conversation) { FB.create(:raif_conversation, creator: creator) }
    let(:tool_invoker) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }
    let(:eval_set_instance) do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval_result, Raif::Evals::EvalResult.new(description: "test"))
      instance
    end

    it "passes when tool is not invoked" do
      eval_set_instance.expect_no_tool_invocation(tool_invoker, "test_model_tool")

      result = eval_set_instance.current_eval_result.expectation_results.first
      expect(result.passed?).to be true
      expect(result.description).to eq("does not invoke test_model_tool")
    end

    it "fails when tool is invoked" do
      FB.create(
        :raif_model_tool_invocation,
        source: tool_invoker,
        tool_type: "Raif::TestModelTool"
      )

      eval_set_instance.expect_no_tool_invocation(tool_invoker, "test_model_tool")

      result = eval_set_instance.current_eval_result.expectation_results.first
      expect(result.failed?).to be true
    end
  end

  describe "#file" do
    let(:eval_set_instance) { test_eval_set_class.new(output: output) }
    let(:test_file_path) { Rails.root.join("raif_evals", "files", "test.txt") }

    before do
      FileUtils.mkdir_p(Rails.root.join("raif_evals", "files"))
      File.write(test_file_path, "test content")
    end

    after do
      FileUtils.rm(test_file_path)
    end

    it "reads a valid file" do
      expect(eval_set_instance.file("test.txt")).to eq("test content")
    end

    it "handles nested paths" do
      nested_path = Rails.root.join("raif_evals", "files", "nested", "file.txt")
      FileUtils.mkdir_p(nested_path.dirname)
      File.write(nested_path, "nested content")

      expect(eval_set_instance.file("nested/file.txt")).to eq("nested content")

      FileUtils.rm_rf(Rails.root.join("raif_evals", "files", "nested"))
    end

    it "raises ArgumentError for non-existent files" do
      expect { eval_set_instance.file("nonexistent.txt") }.to raise_error(
        ArgumentError,
        "File nonexistent.txt does not exist in raif_evals/files/"
      )
    end

    it "raises ArgumentError for empty filename" do
      expect { eval_set_instance.file("") }.to raise_error(
        ArgumentError,
        "Invalid filename: cannot be empty"
      )
    end

    it "raises ArgumentError for nil filename" do
      expect { eval_set_instance.file(nil) }.to raise_error(
        ArgumentError,
        "Invalid filename: cannot be empty"
      )
    end

    it "raises ArgumentError for directory traversal attempts with .." do
      expect { eval_set_instance.file("../../../etc/passwd") }.to raise_error(
        ArgumentError,
        "Invalid filename: cannot contain '..' or absolute paths"
      )
    end

    it "raises ArgumentError for directory traversal attempts with encoded .." do
      expect { eval_set_instance.file("..%2F..%2Fetc%2Fpasswd") }.to raise_error(
        ArgumentError,
        "Invalid filename: cannot contain '..' or absolute paths"
      )
    end

    it "raises ArgumentError for absolute paths" do
      expect { eval_set_instance.file("/etc/passwd") }.to raise_error(
        ArgumentError,
        "Invalid filename: cannot contain '..' or absolute paths"
      )
    end
  end
end
