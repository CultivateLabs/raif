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
  end

  describe "#expect" do
    it "creates passing expectation results" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test"))

      instance.expect "this passes" do
        true
      end

      eval = instance.current_eval
      expect(eval.expectation_results.size).to eq(1)
      expect(eval.expectation_results.first.passed?).to be true
      expect(output.string).to include("✓ this passes")
    end

    it "creates failing expectation results" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test"))

      instance.expect "this fails" do
        false
      end

      eval = instance.current_eval
      expect(eval.expectation_results.size).to eq(1)
      expect(eval.expectation_results.first.failed?).to be true
      expect(output.string).to include("✗ this fails")
    end

    it "handles errors in expectation blocks" do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test"))

      instance.expect "this errors" do
        raise "Boom!"
      end

      eval = instance.current_eval
      expect(eval.expectation_results.size).to eq(1)
      expect(eval.expectation_results.first.error?).to be true
      expect(output.string).to include("✗ this errors (Error: Boom!)")
    end

    context "with metadata" do
      let(:instance) do
        output = StringIO.new
        instance = test_eval_set_class.new(output: output)
        instance.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test"))
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

  describe "#expect_tool_invocation" do
    let(:creator) { FB.create(:raif_test_user) }
    let(:conversation) { FB.create(:raif_conversation, creator: creator) }
    let(:tool_invoker) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }
    let(:eval_set_instance) do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test"))
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

      result = eval_set_instance.current_eval.expectation_results.first
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
      expect(result.description).to eq("invokes Raif::TestModelTool with {items: [{\"title\" => \"test\", \"description\" => \"test desc\"}]}")
    end
  end

  describe "#expect_no_tool_invocation" do
    let(:creator) { FB.create(:raif_test_user) }
    let(:conversation) { FB.create(:raif_conversation, creator: creator) }
    let(:tool_invoker) { FB.create(:raif_conversation_entry, raif_conversation: conversation, creator: creator) }
    let(:eval_set_instance) do
      output = StringIO.new
      instance = test_eval_set_class.new(output: output)
      instance.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test"))
      instance
    end

    it "passes when tool is not invoked" do
      eval_set_instance.expect_no_tool_invocation(tool_invoker, "test_model_tool")

      result = eval_set_instance.current_eval.expectation_results.first
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

      result = eval_set_instance.current_eval.expectation_results.first
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
