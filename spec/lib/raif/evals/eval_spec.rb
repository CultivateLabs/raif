# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::Eval do
  describe "#initialize" do
    it "creates an eval with description and empty expectation results" do
      eval = described_class.new(description: "test eval")

      expect(eval.description).to eq("test eval")
      expect(eval.expectation_results).to eq([])
    end
  end

  describe "#add_expectation_result" do
    it "adds expectation results" do
      eval = described_class.new(description: "test eval")
      result1 = Raif::Evals::ExpectationResult.new(description: "first", status: :passed)
      result2 = Raif::Evals::ExpectationResult.new(description: "second", status: :failed)

      eval.add_expectation_result(result1)
      eval.add_expectation_result(result2)

      expect(eval.expectation_results).to eq([result1, result2])
    end
  end

  describe "#passed?" do
    it "returns true when all expectations pass" do
      eval = described_class.new(description: "test eval")
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "first", status: :passed)
      )
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "second", status: :passed)
      )

      expect(eval.passed?).to be true
    end

    it "returns false when any expectation fails" do
      eval = described_class.new(description: "test eval")
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "first", status: :passed)
      )
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "second", status: :failed)
      )

      expect(eval.passed?).to be false
    end

    it "returns false when any expectation errors" do
      eval = described_class.new(description: "test eval")
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "first", status: :passed)
      )
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "second", status: :error)
      )

      expect(eval.passed?).to be false
    end

    it "returns true when no expectations" do
      eval = described_class.new(description: "test eval")
      expect(eval.passed?).to be true
    end
  end

  describe "#to_h" do
    it "converts to hash with all data" do
      eval = described_class.new(description: "test eval")
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "first", status: :passed)
      )
      eval.add_expectation_result(
        Raif::Evals::ExpectationResult.new(description: "second", status: :failed)
      )

      expect(eval.to_h).to eq({
        description: "test eval",
        passed: false,
        expectation_results: [
          { description: "first", status: :passed },
          { description: "second", status: :failed }
        ],
        usage: {
          model_completions: 0,
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          total_cost: 0.0
        },
        model_completions: []
      })
    end
  end

  describe "#record_model_completions" do
    let(:eval) { described_class.new(description: "test eval") }

    let(:model_completion) do
      FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        prompt_tokens: 100,
        completion_tokens: 25,
        total_tokens: 125
      )
    end

    it "serializes model completions and aggregates usage" do
      eval.record_model_completions([model_completion])

      expect(eval.model_completions.size).to eq(1)
      serialized = eval.model_completions.first
      expect(serialized[:llm_model_key]).to eq("raif_test_llm")
      expect(serialized[:prompt_tokens]).to eq(100)
      expect(serialized[:completion_tokens]).to eq(25)
      expect(serialized[:messages]).to eq(model_completion.messages)
      expect(serialized[:response]).to eq(model_completion.raw_response)

      expect(eval.usage).to include(
        model_completions: 1,
        prompt_tokens: 100,
        completion_tokens: 25,
        total_tokens: 125
      )
    end

    it "includes serialized completions and usage in to_h" do
      eval.record_model_completions([model_completion])

      hash = eval.to_h
      expect(hash[:model_completions].size).to eq(1)
      expect(hash[:usage][:total_tokens]).to eq(125)
    end
  end
end
