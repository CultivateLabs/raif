# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::EvalSets::LlmJudgeExpectations do
  let(:test_eval_set_class) do
    Class.new(Raif::Evals::EvalSet) do
      def self.name
        "TestEvalSet"
      end
    end
  end

  let(:output) { StringIO.new }
  let(:eval_set) { test_eval_set_class.new(output: output) }
  let(:creator) { FB.create(:raif_test_user) }

  before do
    # Provide a real AR creator that also collects expectation results like Raif::Evals::Eval
    # creator.define_singleton_method(:expectation_results) { @__er ||= [] }
    # creator.define_singleton_method(:add_expectation_result) { |res| expectation_results << res }
    eval_set.instance_variable_set(:@current_eval, Raif::Evals::Eval.new(description: "test description"))
  end

  describe "#expect_llm_judge_passes" do
    before do
      stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _model_completion|
        {
          passes: true,
          reasoning: "Good reasoning",
          confidence: 0.9
        }.to_json
      end
    end

    it "creates an expectation, sets description, and stores judge metadata when available" do
      result = eval_set.expect_llm_judge_passes(
        "test output",
        criteria: "Must be polite",
        examples: [],
        strict: false,
        llm_judge_model_key: :claude,
        additional_context: "customer service"
      )

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.description).to eq("LLM judge: Must be polite")
      expect(result.metadata).to be_a(Hash)
    end

    it "prints low confidence warning when confidence is low" do
      stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _model_completion|
        { passes: true, reasoning: "ok", confidence: 0.3 }.to_json
      end

      eval_set.expect_llm_judge_passes("test output", criteria: "Must be polite")
      expect(output.string).to include("Low confidence:")
    end

    it "prints reasoning when verbose output is enabled" do
      original = Raif.config.evals_verbose_output
      Raif.config.evals_verbose_output = true
      begin
        eval_set.expect_llm_judge_passes("test output", criteria: "Must be polite")
        expect(output.string).to include("Good reasoning")
      ensure
        Raif.config.evals_verbose_output = original
      end
    end
  end

  describe "#expect_llm_judge_score" do
    let(:rubric) do
      Raif::Evals::ScoringRubric.new(
        name: :accuracy,
        description: "Accuracy rubric",
        levels: [
          { score_range: (0..4), description: "low" },
          { score_range: (5..7), description: "mid" },
          { score_range: (8..10), description: "high" }
        ]
      )
    end

    before do
      stub_raif_task(Raif::Evals::LlmJudges::Scored) do |_messages, _model_completion|
        { score: 8, reasoning: "Detailed reasoning", confidence: 0.8 }.to_json
      end
    end

    it "creates a scored expectation with rubric name and minimum score and stores metadata" do
      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: rubric,
        min_passing_score: 7,
        llm_judge_model_key: :claude,
        additional_context: "technical content"
      )

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.description).to eq("LLM judge score (accuracy): >= 7")
      expect(result.metadata).to be_a(Hash)
    end

    it "uses 'custom' in description for a string rubric" do
      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: "Custom rubric string",
        min_passing_score: 7
      )

      expect(result.description).to eq("LLM judge score (custom): >= 7")
    end
  end

  describe "#expect_llm_judge_prefers" do
    before do
      stub_raif_task(Raif::Evals::LlmJudges::Comparative) do |_messages, model_completion|
        judge = model_completion.source # the Comparative judge instance
        { winner: judge.expected_winner, reasoning: "A is clearer", confidence: 0.7 }.to_json
      end
    end

    it "creates a comparative expectation, prints winner when available, and stores metadata" do
      result = eval_set.expect_llm_judge_prefers(
        "content A",
        over: "content B",
        criteria: "Which is clearer?",
        allow_ties: true,
        llm_judge_model_key: :claude,
        additional_context: "user documentation"
      )

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.description).to eq("LLM judge prefers A over B: Which is clearer?")
      expect(result.metadata).to be_a(Hash)
    end
  end
end
