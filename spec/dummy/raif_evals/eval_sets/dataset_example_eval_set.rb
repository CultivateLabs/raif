# frozen_string_literal: true

# Exercised end to end by spec/lib/raif/evals/dataset_run_spec.rb against a stubbed LLM.
# The stubbed joke only mentions chickens, so the atom and monad cases fail their subject
# expectation - a dataset where every case passes cannot show that per-case rates work.
class Raif::Evals::DatasetExampleEvalSet < Raif::Evals::EvalSet
  dataset :topics do
    jsonl("topics.jsonl")
  end

  # setup is shared by every eval in the set, so it gets nil for the non-dataset eval below.
  setup do |eval_case|
    @topic = eval_case ? eval_case["topic"] : nil
  end

  eval "mentions the topic it was given", dataset: :topics do |eval_case|
    task = Raif::TestTask.run

    expect "task completes" do
      task.completed?
    end

    expect "setup received the case" do
      @topic == eval_case["topic"]
    end

    expect "response mentions the subject" do
      task.parsed_response.to_s.downcase.include?(eval_case.expected["subject"])
    end

    score "topic_length", @topic.length

    expect_llm_judge_score(
      task.parsed_response,
      scoring_rubric: Raif::Evals::ScoringRubric.clarity,
      min_passing_score: 4
    )
  end

  eval "runs without a dataset" do
    expect "still works" do
      true
    end
  end
end
