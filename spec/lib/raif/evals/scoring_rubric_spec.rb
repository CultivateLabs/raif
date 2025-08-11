# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ScoringRubric do
  describe "#initialize" do
    it "creates a scoring rubric with name, description, and levels" do
      rubric = described_class.new(
        name: :test_rubric,
        description: "Test rubric description",
        levels: [
          { score_range: (9..10), description: "Excellent" },
          { score_range: (7..8), description: "Good" },
          { score: 5, description: "Average" }
        ]
      )

      expect(rubric.name).to eq(:test_rubric)
      expect(rubric.description).to eq("Test rubric description")
      expect(rubric.levels.length).to eq(3)
    end
  end

  describe "#to_prompt" do
    context "with score ranges" do
      let(:rubric) do
        described_class.new(
          name: :test_rubric,
          description: "Test rubric for evaluation",
          levels: [
            { score_range: (9..10), description: "Excellent performance" },
            { score_range: (7..8), description: "Good performance" },
            { score_range: (5..6), description: "Average performance" }
          ]
        )
      end

      it "formats the rubric as a prompt string" do
        prompt = rubric.to_prompt
        expected = <<~PROMPT.strip
          Test rubric for evaluation

          Scoring levels:
          - 9-10: Excellent performance
          - 7-8: Good performance
          - 5-6: Average performance
        PROMPT
        expect(prompt).to eq(expected)
      end
    end

    context "with single scores" do
      let(:rubric) do
        described_class.new(
          name: :binary_rubric,
          description: "Simple pass/fail rubric",
          levels: [
            { score: 1, description: "Pass" },
            { score: 0, description: "Fail" }
          ]
        )
      end

      it "formats single score levels correctly" do
        prompt = rubric.to_prompt
        expected = <<~PROMPT.strip
          Simple pass/fail rubric

          Scoring levels:
          - 1: Pass
          - 0: Fail
        PROMPT

        expect(prompt).to eq(expected)
      end
    end

    context "with exclusive ranges" do
      let(:rubric) do
        described_class.new(
          name: :exclusive_rubric,
          description: "Rubric with exclusive ranges",
          levels: [
            { score_range: (9...11), description: "Top tier" }
          ]
        )
      end

      it "handles exclusive ranges correctly" do
        prompt = rubric.to_prompt
        expected = <<~PROMPT.strip
          Rubric with exclusive ranges

          Scoring levels:
          - 9-10: Top tier
        PROMPT
        expect(prompt).to eq(expected)
      end
    end

    context "with invalid level format" do
      it "raises an error for levels without score or score_range" do
        rubric = described_class.new(
          name: :invalid_rubric,
          description: "Invalid rubric",
          levels: [
            { description: "No score specified" }
          ]
        )

        expect { rubric.to_prompt }.to raise_error(ArgumentError, /level must include :score or :score_range/)
      end
    end
  end

  describe "factory methods" do
    describe ".accuracy" do
      let(:rubric) { described_class.accuracy }

      it "creates an accuracy rubric" do
        expect(rubric.name).to eq(:accuracy)
        expect(rubric.description).to include("factual correctness")
        expect(rubric.levels.length).to eq(5)
      end

      it "has appropriate score ranges" do
        prompt = rubric.to_prompt
        expected = <<~PROMPT.strip
          Evaluates factual correctness and precision

          Scoring levels:
          - 9-10: Completely accurate with no errors
          - 7-8: Mostly accurate with minor imprecisions
          - 5-6: Generally accurate but some notable errors
          - 3-4: Significant inaccuracies present
          - 0-2: Mostly or entirely inaccurate
        PROMPT

        expect(prompt).to eq(expected)
      end
    end

    describe ".helpfulness" do
      let(:rubric) { described_class.helpfulness }

      it "creates a helpfulness rubric" do
        expect(rubric.name).to eq(:helpfulness)
        expect(rubric.description).to include("addresses user needs")
        expect(rubric.levels.length).to eq(5)
      end
    end

    describe ".clarity" do
      let(:rubric) { described_class.clarity }

      it "creates a clarity rubric" do
        expect(rubric.name).to eq(:clarity)
        expect(rubric.description).to include("clarity and comprehensibility")
        expect(rubric.levels.length).to eq(5)
      end
    end
  end
end
