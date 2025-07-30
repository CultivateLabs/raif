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

      eval_set_instance.expect_tool_invocation(tool_invoker, "test_model_tool")

      result = eval_set_instance.current_eval.expectation_results.first
      expect(result.passed?).to be true
      expect(result.description).to eq("invokes test_model_tool")
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

      eval_set_instance.expect_tool_invocation(
        tool_invoker,
        "test_model_tool",
        with: { items: [{ "title" => "test", "description" => "test desc" }] }
      )

      result = eval_set_instance.current_eval.expectation_results.first
      expect(result.passed?).to be true
      expect(result.description).to include("invokes test_model_tool with")
      expect(result.description).to include("items")
      expect(result.description).to include("test")
      expect(result.description).to include("test desc")
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
end
