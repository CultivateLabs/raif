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
        ]
      })
    end
  end
end
