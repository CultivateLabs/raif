# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::LlmJudges::Binary do
  describe "json_response_schema" do
    it "returns a JSON response schema" do
      judge = described_class.new
      expect(judge.json_response_schema).to eq({
        type: "object",
        additionalProperties: false,
        properties: {
          passes: { type: "boolean", description: "Whether the content passes the criteria" },
          reasoning: { type: "string", description: "Detailed explanation of the judgment" },
          confidence: { type: "number", description: "Confidence level from 0.0 to 1.0", minimum: 0, maximum: 1 }
        },
        required: ["passes", "reasoning", "confidence"]
      })
    end
  end

  describe "#build_system_prompt" do
    let(:judge) { described_class.new }

    it "returns a system prompt for binary evaluation" do
      prompt = judge.build_system_prompt

      expected_prompt = <<~PROMPT.strip
        You are an expert evaluator assessing whether content meets specific criteria.
        Your task is to make binary pass/fail judgments with clear reasoning.

        First, provide detailed reasoning/explanation of your evaluation. Then, provide a precise pass/fail judgment.

        Respond with JSON matching this schema:
        {
          "passes": boolean,
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
        criteria: "The response must be polite and professional",
        content_to_judge: "Hello, how can I help you today?",
        strict_mode: false,
        examples: nil,
        additional_context: nil
      )
    end

    context "with strict mode disabled" do
      it "contains appropriate content" do
        prompt = judge.build_prompt

        expected_prompt = <<~PROMPT.strip
          Evaluation criteria: The response must be polite and professional

          Apply reasonable judgment while adhering to the criteria.

          Now evaluate this content:
          Hello, how can I help you today?

          Does this content meet the evaluation criteria?
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end

    context "with strict mode enabled" do
      before { judge.strict_mode = true }

      it "includes strict mode instruction" do
        prompt = judge.build_prompt

        expected_prompt = <<~PROMPT.strip
          Evaluation criteria: The response must be polite and professional

          Apply the criteria strictly without any leniency.

          Now evaluate this content:
          Hello, how can I help you today?

          Does this content meet the evaluation criteria?
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end

    context "with examples provided" do
      let(:examples) do
        [
          { output: "Thank you for your patience", passes: true, reasoning: "Polite tone" },
          { output: "Whatever, figure it out", passes: false, reasoning: "Dismissive and unprofessional" }
        ]
      end

      before { judge.examples = examples }

      it "includes formatted examples" do
        prompt = judge.build_prompt

        expected_prompt = <<~PROMPT.strip
          Evaluation criteria: The response must be polite and professional

          Apply reasonable judgment while adhering to the criteria.

          Here are examples of how to evaluate:
          Output: Thank you for your patience
          Reasoning: Polite tone
          Judgment: PASS

          Output: Whatever, figure it out
          Reasoning: Dismissive and unprofessional
          Judgment: FAIL

          Now evaluate this content:
          Hello, how can I help you today?

          Does this content meet the evaluation criteria?
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end

    context "with additional context" do
      before { judge.additional_context = "This is a customer service interaction" }

      it "includes the additional context" do
        prompt = judge.build_prompt

        expected_prompt = <<~PROMPT.strip
          Evaluation criteria: The response must be polite and professional

          Apply reasonable judgment while adhering to the criteria.

          Additional context:
          This is a customer service interaction

          Now evaluate this content:
          Hello, how can I help you today?

          Does this content meet the evaluation criteria?
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end
  end

  describe "#passes?" do
    let(:judge) { described_class.new }

    context "when completed and passes is true" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "passes" => true })
      end

      it "returns true" do
        expect(judge.passes?).to be true
      end
    end

    context "when completed and passes is false" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "passes" => false })
      end

      it "returns false" do
        expect(judge.passes?).to be false
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.passes?).to be_nil
      end
    end
  end
end
