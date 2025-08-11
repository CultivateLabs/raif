# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::LlmJudge do
  describe "class configuration" do
    it "sets temperature to 0.0 for consistent judging" do
      judge = described_class.new
      expect(judge.temperature).to eq(0.0)
    end

    it "uses JSON response format" do
      judge = described_class.new
      expect(judge.response_format).to eq("json")
    end
  end

  describe "#default_llm_model_key" do
    let(:judge) { described_class.new }

    context "when evals_default_llm_judge_model_key is configured" do
      before do
        allow(Raif.config).to receive(:evals_default_llm_judge_model_key).and_return(:claude_3_5_sonnet)
      end

      it "uses the configured judge model key" do
        expect(judge.default_llm_model_key).to eq(:claude_3_5_sonnet)
      end
    end

    context "when evals_default_llm_judge_model_key is not configured" do
      before do
        allow(Raif.config).to receive(:evals_default_llm_judge_model_key).and_return(nil)
      end

      it "falls back to the default task model key" do
        expect(judge.default_llm_model_key).to eq(:raif_test_llm)
      end
    end
  end

  describe "#judgment_reasoning" do
    let(:judge) { described_class.new }

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "reasoning" => "The output is well-structured" })
      end

      it "returns the reasoning from parsed response" do
        expect(judge.judgment_reasoning).to eq("The output is well-structured")
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.judgment_reasoning).to be_nil
      end
    end
  end

  describe "#judgment_confidence" do
    let(:judge) { described_class.new }

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "confidence" => 0.85 })
      end

      it "returns the confidence from parsed response" do
        expect(judge.judgment_confidence).to eq(0.85)
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.judgment_confidence).to be_nil
      end
    end
  end

  describe "#low_confidence?" do
    let(:judge) { described_class.new }

    context "when confidence is below 0.5" do
      before do
        allow(judge).to receive(:judgment_confidence).and_return(0.3)
      end

      it "returns true" do
        expect(judge.low_confidence?).to be true
      end
    end

    context "when confidence is 0.5 or above" do
      before do
        allow(judge).to receive(:judgment_confidence).and_return(0.7)
      end

      it "returns false" do
        expect(judge.low_confidence?).to be false
      end
    end

    context "when confidence is nil" do
      before do
        allow(judge).to receive(:judgment_confidence).and_return(nil)
      end

      it "returns falsey" do
        expect(judge.low_confidence?).to be_falsey
      end
    end
  end
end
