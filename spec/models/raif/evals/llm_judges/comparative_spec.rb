# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::LlmJudges::Comparative do
  describe "A/B randomization" do
    let(:judge) do
      described_class.new(
        content_to_judge: "Content to judge",
        over_content: "Content to compare against",
        comparison_criteria: "Which is clearer?",
        allow_ties: false
      )
    end

    it "randomly assigns expected_winner" do
      judge.run_callbacks(:create) { false }
      expect(["A", "B"]).to include(judge.expected_winner)
    end

    it "assigns content_to_judge to content_a" do
      allow_any_instance_of(Array).to receive(:sample).and_return("A")
      judge.run_callbacks(:create) { false }
      expect(judge.content_a).to eq("Content to judge")
      expect(judge.content_b).to eq("Content to compare against")
    end

    it "assigns over_content to content_a" do
      allow_any_instance_of(Array).to receive(:sample).and_return("B")
      judge.run_callbacks(:create) { false }
      expect(judge.content_a).to eq("Content to compare against")
      expect(judge.content_b).to eq("Content to judge")
    end
  end

  describe "#build_system_prompt" do
    let(:judge) { described_class.new(allow_ties: false) }

    context "when ties are allowed" do
      before { judge.allow_ties = true }

      it "includes tie allowance instruction" do
        prompt = judge.build_system_prompt
        expected_prompt = <<~PROMPT.strip
          You are an expert evaluator comparing two pieces of content to determine which better meets specified criteria.

          You may declare a tie if both pieces of content are equally good.

          First, provide detailed reasoning for your choice. Then, provide a precise winner (A, B, or tie).

          Respond with JSON matching the required schema.
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end

    context "when ties are not allowed" do
      before { judge.allow_ties = false }

      it "includes must-choose instruction" do
        prompt = judge.build_system_prompt
        expected_prompt = <<~PROMPT.strip
          You are an expert evaluator comparing two pieces of content to determine which better meets specified criteria.

          You must choose a winner even if the difference is minimal.

          First, provide detailed reasoning for your choice. Then, provide a precise winner (A or B).

          Respond with JSON matching the required schema.
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end
  end

  describe "#build_prompt" do
    let(:judge) do
      described_class.new(
        content_to_judge: "Content to judge",
        over_content: "Content to compare against",
        comparison_criteria: "Which response is more helpful?",
        allow_ties: false
      )
    end

    before do
      judge.content_a = judge.content_to_judge
      judge.content_b = judge.over_content
    end

    it "contains appropriate content" do
      prompt = judge.build_prompt
      expected_prompt = <<~PROMPT.strip
        Comparison criteria: Which response is more helpful?

        Compare the following two pieces of content:

        CONTENT A:
        Content to judge

        CONTENT B:
        Content to compare against

        Which content better meets the comparison criteria?
      PROMPT

      expect(prompt).to eq(expected_prompt)
    end

    context "with additional context" do
      before { judge.additional_context = "Consider user experience" }

      it "includes the additional context" do
        prompt = judge.build_prompt
        expected_prompt = <<~PROMPT.strip
          Comparison criteria: Which response is more helpful?

          Additional context:
          Consider user experience

          Compare the following two pieces of content:

          CONTENT A:
          Content to judge

          CONTENT B:
          Content to compare against

          Which content better meets the comparison criteria?
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end
  end

  describe "#winner" do
    let(:judge) { described_class.new }

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "winner" => "A" })
      end

      it "returns the winner from parsed response" do
        expect(judge.winner).to eq("A")
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.winner).to be_nil
      end
    end
  end

  describe "#tie?" do
    let(:judge) { described_class.new }

    context "when winner is tie" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "winner" => "tie" })
      end

      it "returns true" do
        expect(judge.tie?).to be true
      end
    end

    context "when winner is not tie" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "winner" => "A" })
      end

      it "returns false" do
        expect(judge.tie?).to be false
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.tie?).to be_nil
      end
    end
  end

  describe "#correct_expected_winner?" do
    let(:judge) { described_class.new }

    before { judge.expected_winner = "A" }

    context "when winner matches expected" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "winner" => "A" })
      end

      it "returns true" do
        expect(judge.correct_expected_winner?).to be true
      end
    end

    context "when winner does not match expected" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return({ "winner" => "B" })
      end

      it "returns false" do
        expect(judge.correct_expected_winner?).to be false
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      it "returns nil" do
        expect(judge.correct_expected_winner?).to be_nil
      end
    end
  end
end
