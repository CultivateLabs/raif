# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::LlmJudges::Scored do
  describe "#build_system_prompt" do
    let(:judge) { described_class.new }

    it "returns a system prompt for scored evaluation" do
      prompt = judge.build_system_prompt

      expected_prompt = <<~PROMPT.strip
        You are an expert evaluator providing numerical scores based on a detailed rubric.

        First, provide detailed reasoning/explanation of your evaluation. Then, provide a precise score according to the provided rubric.

        Respond with JSON matching this schema:
        {
          "score": number,
          "reasoning": "detailed explanation",
          "confidence": 0.0-1.0
        }
      PROMPT

      expect(prompt).to eq(expected_prompt)
    end
  end

  describe "#build_prompt" do
    let(:judge) do
      described_class.new(
        scoring_rubric: scoring_rubric,
        content_to_judge: "This is the content to evaluate",
        additional_context: additional_context
      )
    end

    let(:additional_context) { nil }

    context "with a string rubric" do
      let(:scoring_rubric) { "Score 9-10: Excellent\nScore 7-8: Good" }

      it "includes appropriate content" do
        prompt = judge.build_prompt

        expected_prompt = <<~PROMPT.strip
          Scoring rubric:
          Score 9-10: Excellent
          Score 7-8: Good

          Evaluate the following content according to the scoring rubric:
          This is the content to evaluate

          Provide your score and detailed reasoning.
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end

    context "with a ScoringRubric object" do
      let(:scoring_rubric) do
        Raif::Evals::ScoringRubric.new(
          name: :test_rubric,
          description: "Test description",
          levels: [{ score_range: (9..10), description: "Excellent" }]
        )
      end

      it "formats the rubric using to_prompt" do
        prompt = judge.build_prompt
        expected_prompt = <<~PROMPT.strip
          Scoring rubric:
          Test description

          Scoring levels:
          - 9-10: Excellent

          Evaluate the following content according to the scoring rubric:
          This is the content to evaluate

          Provide your score and detailed reasoning.
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end

      context "with additional context" do
        let(:additional_context) { "Consider technical accuracy" }

        it "includes the additional context" do
          prompt = judge.build_prompt
          expected_prompt = <<~PROMPT.strip
            Scoring rubric:
            Test description

            Scoring levels:
            - 9-10: Excellent

            Additional context:
            Consider technical accuracy

            Evaluate the following content according to the scoring rubric:
            This is the content to evaluate

            Provide your score and detailed reasoning.
          PROMPT
          expect(prompt).to eq(expected_prompt)
        end
      end
    end
  end

  describe "#judgment_score" do
    let(:judge) { described_class.new }

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "score" => 8 })
      end

      it "returns the score from parsed response" do
        expect(judge.judgment_score).to eq(8)
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.judgment_score).to be_nil
      end
    end
  end
end
