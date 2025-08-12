# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::EvalSets::LlmJudgeExpectations do
  let(:test_eval_set_class) do
    Class.new(Raif::Evals::EvalSet) do
      def self.name
        "TestEvalSet"
      end

      def initialize(output: $stdout)
        super

        @current_eval = Raif::Evals::Eval.new(description: "test description")
      end
    end
  end

  let(:output) { StringIO.new }
  let(:eval_set) { test_eval_set_class.new(output: output) }

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
      expect(Raif::Task.count).to eq(0)

      result = eval_set.expect_llm_judge_passes(
        "test output",
        criteria: "Must be polite",
        examples: [],
        strict: false,
        llm_judge_model_key: :raif_test_llm,
        additional_context: "customer service"
      )

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.passed?).to eq(true)
      expect(result.description).to eq("LLM judge: Must be polite")
      expect(result.metadata).to eq({ passes: true, reasoning: "Good reasoning", confidence: 0.9 })

      expect(Raif::Task.count).to eq(1)

      task = Raif::Task.last
      expect(task.type).to eq("Raif::Evals::LlmJudges::Binary")
      expect(task.response_format).to eq("json")
      expect(task.started_at).to be_present
      expect(task.completed_at).to be_present
      expect(task.llm_model_key).to eq("raif_test_llm")
    end

    it "fails if the task fails" do
      result = eval_set.expect_llm_judge_passes(
        "test output",
        criteria: "Must be polite",
        llm_judge_model_key: :invalid
      )

      expect(result.passed?).to eq(false)
      expect(result.failed?).to eq(true)
      expect(result.error_message).to eq("Llm model key is not included in the list")
    end

    it "prints low confidence warning when confidence is low" do
      stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _model_completion|
        { passes: true, reasoning: "ok", confidence: 0.3 }.to_json
      end

      eval_set.expect_llm_judge_passes("test output", criteria: "Must be polite")
      expect(output.string).to include("Low confidence:")
    end

    it "prints reasoning when verbose output is enabled" do
      allow(Raif.config).to receive(:evals_verbose_output).and_return(true)
      eval_set.expect_llm_judge_passes("test output", criteria: "Must be polite")
      expect(output.string).to include("Good reasoning")
    end

    it "merges user metadata with judge metadata" do
      stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _model_completion|
        { passes: true, reasoning: "Good", confidence: 0.85 }.to_json
      end

      result = eval_set.expect_llm_judge_passes(
        "test output",
        criteria: "Must be polite",
        result_metadata: { user_context: "customer support", priority: "high" }
      )

      expect(result.metadata).to eq({
        user_context: "customer support",
        priority: "high",
        passes: true,
        reasoning: "Good",
        confidence: 0.85
      })
    end

    it "allows user metadata to override judge metadata if keys conflict" do
      stub_raif_task(Raif::Evals::LlmJudges::Binary) do |_messages, _model_completion|
        { passes: true, reasoning: "Auto reasoning", confidence: 0.9 }.to_json
      end

      result = eval_set.expect_llm_judge_passes(
        "test output",
        criteria: "Must be polite",
        result_metadata: { reasoning: "Custom reasoning override", custom_field: "test" }
      )

      expect(result.metadata[:reasoning]).to eq("Auto reasoning")
      expect(result.metadata[:custom_field]).to eq("test")
      expect(result.metadata[:passes]).to eq(true)
      expect(result.metadata[:confidence]).to eq(0.9)
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
      expect(Raif::Task.count).to eq(0)

      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: rubric,
        min_passing_score: 7,
        llm_judge_model_key: :raif_test_llm,
        additional_context: "technical content"
      )

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.passed?).to eq(true)
      expect(result.description).to eq("LLM judge score (accuracy): >= 7")
      expect(result.metadata).to eq({ score: 8, reasoning: "Detailed reasoning", confidence: 0.8 })

      expect(Raif::Task.count).to eq(1)

      task = Raif::Task.last
      expect(task.type).to eq("Raif::Evals::LlmJudges::Scored")
      expect(task.response_format).to eq("json")
      expect(task.started_at).to be_present
      expect(task.completed_at).to be_present
      expect(task.llm_model_key).to eq("raif_test_llm")
    end

    it "uses 'custom' in description for a string rubric" do
      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: "Custom rubric string",
        min_passing_score: 7
      )

      expect(result.description).to eq("LLM judge score (custom): >= 7")
    end

    it "fails if the task fails" do
      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: rubric,
        min_passing_score: 7,
        llm_judge_model_key: :invalid
      )

      expect(result.passed?).to eq(false)
      expect(result.failed?).to eq(true)
      expect(result.error_message).to include("Llm model key is not included in the list")
    end

    it "fails when score is below minimum passing score" do
      stub_raif_task(Raif::Evals::LlmJudges::Scored) do |_messages, _model_completion|
        { score: 5, reasoning: "Below threshold", confidence: 0.9 }.to_json
      end

      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: rubric,
        min_passing_score: 7
      )

      expect(result.passed?).to eq(false)
      expect(result.failed?).to eq(true)
      expect(result.metadata).to eq({ score: 5, reasoning: "Below threshold", confidence: 0.9 })
    end

    it "merges user metadata with judge metadata for scoring" do
      stub_raif_task(Raif::Evals::LlmJudges::Scored) do |_messages, _model_completion|
        { score: 9, reasoning: "Excellent", confidence: 0.95 }.to_json
      end

      result = eval_set.expect_llm_judge_score(
        "test output",
        scoring_rubric: rubric,
        min_passing_score: 7,
        result_metadata: { test_id: "test_123", category: "accuracy" }
      )

      expect(result.metadata).to eq({
        test_id: "test_123",
        category: "accuracy",
        score: 9,
        reasoning: "Excellent",
        confidence: 0.95
      })
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
      expect(Raif::Task.count).to eq(0)

      result = eval_set.expect_llm_judge_prefers(
        "content A",
        over: "content B",
        criteria: "Which is clearer?",
        allow_ties: true,
        llm_judge_model_key: :raif_test_llm,
        additional_context: "user documentation"
      )

      expect(result).to be_a(Raif::Evals::ExpectationResult)
      expect(result.passed?).to eq(true)
      expect(result.description).to eq("LLM judge prefers A over B: Which is clearer?")
      expect(result.metadata[:winner]).to be_in(["A", "B"])
      expect(result.metadata[:reasoning]).to eq("A is clearer")
      expect(result.metadata[:confidence]).to eq(0.7)

      expect(Raif::Task.count).to eq(1)

      task = Raif::Task.last
      expect(task.type).to eq("Raif::Evals::LlmJudges::Comparative")
      expect(task.response_format).to eq("json")
      expect(task.started_at).to be_present
      expect(task.completed_at).to be_present
      expect(task.llm_model_key).to eq("raif_test_llm")
    end

    it "fails if the task fails" do
      result = eval_set.expect_llm_judge_prefers(
        "content A",
        over: "content B",
        criteria: "Which is clearer?",
        llm_judge_model_key: :invalid
      )

      expect(result.passed?).to eq(false)
      expect(result.failed?).to eq(true)
      expect(result.error_message).to include("Llm model key is not included in the list")
    end

    it "fails when judge prefers the wrong option" do
      stub_raif_task(Raif::Evals::LlmJudges::Comparative) do |_messages, model_completion|
        judge = model_completion.source
        # Return the opposite of expected_winner to make it fail
        wrong_winner = judge.expected_winner == "A" ? "B" : "A"
        { winner: wrong_winner, reasoning: "Wrong choice", confidence: 0.8 }.to_json
      end

      result = eval_set.expect_llm_judge_prefers(
        "content A",
        over: "content B",
        criteria: "Which is clearer?"
      )

      expect(result.passed?).to eq(false)
      expect(result.failed?).to eq(true)
      expect(result.metadata[:winner]).to be_in(["A", "B"])
      expect(result.metadata[:reasoning]).to eq("Wrong choice")
      expect(result.metadata[:confidence]).to eq(0.8)
    end

    it "merges user metadata with judge metadata for comparisons" do
      stub_raif_task(Raif::Evals::LlmJudges::Comparative) do |_messages, model_completion|
        judge = model_completion.source
        { winner: judge.expected_winner, reasoning: "Clear winner", confidence: 0.88 }.to_json
      end

      result = eval_set.expect_llm_judge_prefers(
        "content A",
        over: "content B",
        criteria: "Which is clearer?",
        result_metadata: { comparison_type: "clarity", test_run: 42 }
      )

      expect(result.metadata).to include({
        comparison_type: "clarity",
        test_run: 42,
        reasoning: "Clear winner",
        confidence: 0.88
      })
      expect(result.metadata[:winner]).to be_in(["A", "B"])
    end
  end
end
