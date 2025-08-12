# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::LlmJudges::Summarization do
  describe ".run" do
    it "runs the judge" do
      stub_raif_task(Raif::Evals::LlmJudges::Summarization) do |_messages, _model_completion|
        {
          "coverage": {
            "justification": "coverage justification text",
            "score": 3
          },
          "accuracy": {
            "justification": "accuracy justification text",
            "score": 2
          },
          "clarity": {
            "justification": "clarity justification text",
            "score": 4
          },
          "conciseness": {
            "justification": "conciseness justification text",
            "score": 5
          },
          "overall": {
            "justification": "overall justification text",
            "score": 3
          }
        }.to_json
      end

      judge_task = Raif::Evals::LlmJudges::Summarization.run(
        original_content: "original content text",
        summary: "summary text",
        additional_context: "some additional context"
      )

      expect(judge_task.completed?).to be(true)
      expect(judge_task.coverage_score).to eq(3)
      expect(judge_task.accuracy_score).to eq(2)
      expect(judge_task.clarity_score).to eq(4)
      expect(judge_task.conciseness_score).to eq(5)
      expect(judge_task.overall_score).to eq(3)
      expect(judge_task.coverage_justification).to eq("coverage justification text")
      expect(judge_task.accuracy_justification).to eq("accuracy justification text")
      expect(judge_task.clarity_justification).to eq("clarity justification text")
      expect(judge_task.conciseness_justification).to eq("conciseness justification text")
      expect(judge_task.overall_justification).to eq("overall justification text")
    end
  end

  describe "#build_system_prompt" do
    let(:judge) { described_class.new }

    it "returns a system prompt for summarization evaluation" do
      prompt = judge.build_system_prompt

      expected_prompt = <<~PROMPT.strip
        You are an impartial expert judge of summary quality. You'll be provided a original piece of content and its summary. Your job is to evaluate the summary against the original content based on the following criteria, and assign a score from 1 to 5 for each (5 = excellent, 1 = very poor):

        **Coverage (Relevance & Completeness):** Does the summary capture all the important points of the original content?
        - 5 = Excellent Coverage - Nearly all key points and essential details from the content are present in the summary, with no major omissions.
        - 4 = Good Coverage - Most important points are included, but a minor detail or two might be missing.
        - 3 = Fair Coverage - Some main points appear, but the summary misses or glosses over other important information.
        - 2 = Poor Coverage - Many critical points from the content are missing; the summary is incomplete.
        - 1 = Very Poor - The summary fails to include most of the content's main points (highly incomplete).

        **Accuracy (Faithfulness to the Source):** Is the summary factually correct and free of hallucinations or misrepresentations of the content?
        - 5 = Fully Accurate - All statements in the summary are correct and directly supported by the content. No errors or invented information.
        - 4 = Mostly Accurate - The summary is generally accurate with perhaps one minor error or slight ambiguity, but no significant falsehoods.
        - 3 = Some Inaccuracies - Contains a few errors or unsupported claims from the content, but overall captures the gist correctly.
        - 2 = Mostly Inaccurate - Multiple statements in the summary are incorrect or not supported by the content.
        - 1 = Completely Inaccurate - The summary seriously distorts or contradicts the content; many claims are false or not in the source.

        **Clarity and Coherence:** Is the summary well-written and easy to understand? (Consider organization, flow, and whether it would make sense to a reader.)
        - 5 = Very Clear & Coherent - The summary is logically organized, flows well, and would be easily understood by the target reader. No confusion or ambiguity.
        - 4 = Mostly Clear - Readable and mostly well-structured, though a sentence or transition could be smoother.
        - 3 = Somewhat Clear - The summary makes sense overall but might be disjointed or awkward in places, requiring effort to follow.
        - 2 = Generally Unclear - Lacks coherence or has poor phrasing that makes it hard to follow the ideas.
        - 1 = Very Poor Clarity - The summary is very confusing or poorly structured, making it hard to understand.

        **Conciseness:** Is the summary succinct while still informative? (It should omit unnecessary detail but not at the expense of coverage.)
        - 5 = Highly Concise - The summary is brief yet covers all important information (no fluff or redundancy).
        - 4 = Concise - Generally to-the-point, with only minor redundancy or superfluous content.
        - 3 = Moderately Concise - Some excess detail or repetition that could be trimmed, but not egregious.
        - 2 = Verbose - Contains a lot of unnecessary detail or repeats points, making it longer than needed.
        - 1 = Excessively Verbose - The summary is overly long or wordy, with much content that doesn't add value.
      PROMPT

      expect(prompt).to eq(expected_prompt)
    end
  end

  describe "#build_prompt" do
    let(:judge) do
      described_class.new(
        original_content: "This is the original content that needs to be summarized",
        summary: "This is the summary",
        additional_context: additional_context
      )
    end

    let(:additional_context) { nil }

    it "includes appropriate content" do
      prompt = judge.build_prompt

      expected_prompt = <<~PROMPT.strip
        # Instructions
        Below is an original piece of content and its summary. Evaluate the summary against the original content based on our 4 criteria. For each, you should provide:
        - A brief justification (1-3 sentences) noting any relevant observations (e.g. what was missing, incorrect, unclear, or well-done).
        - A score from 1 to 5 (5 = excellent, 1 = very poor).

        Finally, provide an **overall evaluation** of the summary, consisting of a brief justification (1-3 sentences) and a score from 1 to 5 (5 = excellent, 1 = very poor).

        # Output Format
        Format your output as a JSON object with the following keys:
        {
          "coverage": {
            "justification": "...",
            "score": 1-5
          },
          "accuracy": {
            "justification": "...",
            "score": 1-5
          },
          "clarity": {
            "justification": "...",
            "score": 1-5
          },
          "conciseness": {
            "justification": "...",
            "score": 1-5
          },
          "overall": {
            "justification": "...",
            "score": 1-5
          }
        }

        # Original Article/Document
        This is the original content that needs to be summarized

        # Summary to Evaluate
        This is the summary
      PROMPT

      expect(prompt).to eq(expected_prompt)
    end

    context "with additional context" do
      let(:additional_context) { "Focus on technical accuracy" }

      it "includes the additional context" do
        prompt = judge.build_prompt

        expected_prompt = <<~PROMPT.strip
          # Instructions
          Below is an original piece of content and its summary. Evaluate the summary against the original content based on our 4 criteria. For each, you should provide:
          - A brief justification (1-3 sentences) noting any relevant observations (e.g. what was missing, incorrect, unclear, or well-done).
          - A score from 1 to 5 (5 = excellent, 1 = very poor).

          Finally, provide an **overall evaluation** of the summary, consisting of a brief justification (1-3 sentences) and a score from 1 to 5 (5 = excellent, 1 = very poor).

          # Output Format
          Format your output as a JSON object with the following keys:
          {
            "coverage": {
              "justification": "...",
              "score": 1-5
            },
            "accuracy": {
              "justification": "...",
              "score": 1-5
            },
            "clarity": {
              "justification": "...",
              "score": 1-5
            },
            "conciseness": {
              "justification": "...",
              "score": 1-5
            },
            "overall": {
              "justification": "...",
              "score": 1-5
            }
          }

          # Additional context:
          Focus on technical accuracy

          # Original Article/Document
          This is the original content that needs to be summarized

          # Summary to Evaluate
          This is the summary
        PROMPT

        expect(prompt).to eq(expected_prompt)
      end
    end
  end

  describe "scoring accessor methods" do
    let(:judge) { described_class.new }
    let(:parsed_response) do
      {
        "coverage" => {
          "justification" => "Good coverage",
          "score" => 4
        },
        "accuracy" => {
          "justification" => "Very accurate",
          "score" => 5
        },
        "clarity" => {
          "justification" => "Clear and coherent",
          "score" => 4
        },
        "conciseness" => {
          "justification" => "Appropriately concise",
          "score" => 4
        },
        "overall" => {
          "justification" => "Excellent summary",
          "score" => 4
        }
      }
    end

    context "when completed" do
      before do
        allow(judge).to receive(:completed?).and_return(true)
        allow(judge).to receive(:parsed_response).and_return(parsed_response)
      end

      describe "#overall_score" do
        it "returns the overall score" do
          expect(judge.overall_score).to eq(4)
        end
      end

      describe "#overall_justification" do
        it "returns the overall justification" do
          expect(judge.overall_justification).to eq("Excellent summary")
        end
      end

      describe "#coverage_score" do
        it "returns the coverage score" do
          expect(judge.coverage_score).to eq(4)
        end
      end

      describe "#coverage_justification" do
        it "returns the coverage justification" do
          expect(judge.coverage_justification).to eq("Good coverage")
        end
      end

      describe "#accuracy_score" do
        it "returns the accuracy score" do
          expect(judge.accuracy_score).to eq(5)
        end
      end

      describe "#accuracy_justification" do
        it "returns the accuracy justification" do
          expect(judge.accuracy_justification).to eq("Very accurate")
        end
      end

      describe "#clarity_score" do
        it "returns the clarity score" do
          expect(judge.clarity_score).to eq(4)
        end
      end

      describe "#conciseness_score" do
        it "returns the conciseness score" do
          expect(judge.conciseness_score).to eq(4)
        end
      end

      describe "#conciseness_justification" do
        it "returns the conciseness justification" do
          expect(judge.conciseness_justification).to eq("Appropriately concise")
        end
      end
    end

    context "when not completed" do
      before do
        allow(judge).to receive(:completed?).and_return(false)
      end

      describe "#overall_score" do
        it "returns nil" do
          expect(judge.overall_score).to be_nil
        end
      end

      describe "#overall_justification" do
        it "returns nil" do
          expect(judge.overall_justification).to be_nil
        end
      end

      describe "#coverage_score" do
        it "returns nil" do
          expect(judge.coverage_score).to be_nil
        end
      end

      describe "#coverage_justification" do
        it "returns nil" do
          expect(judge.coverage_justification).to be_nil
        end
      end

      describe "#accuracy_score" do
        it "returns nil" do
          expect(judge.accuracy_score).to be_nil
        end
      end

      describe "#accuracy_justification" do
        it "returns nil" do
          expect(judge.accuracy_justification).to be_nil
        end
      end

      describe "#clarity_score" do
        it "returns nil" do
          expect(judge.clarity_score).to be_nil
        end
      end

      describe "#conciseness_score" do
        it "returns nil" do
          expect(judge.conciseness_score).to be_nil
        end
      end

      describe "#conciseness_justification" do
        it "returns nil" do
          expect(judge.conciseness_justification).to be_nil
        end
      end
    end
  end
end
