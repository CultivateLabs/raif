# frozen_string_literal: true

module Raif
  module Evals
    module LlmJudges
      class Summarization < Raif::Evals::LlmJudge
        task_run_arg :original_content # the original content to evaluate the summary against
        task_run_arg :summary # the summary to evaluate against the original content

        json_response_schema do
          object :coverage do
            string :justification, description: "Justification for the score"
            number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
          end

          object :accuracy do
            string :justification, description: "Justification for the score"
            number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
          end

          object :clarity do
            string :justification, description: "Justification for the score"
            number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
          end

          object :conciseness do
            string :justification, description: "Justification for the score"
            number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
          end

          object :overall do
            string :justification, description: "Justification for the score"
            number :score, description: "Score from 1 to 5", enum: [1, 2, 3, 4, 5]
          end
        end

        def build_system_prompt
          <<~PROMPT.strip
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
        end

        def build_prompt
          <<~PROMPT.strip
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
            #{additional_context_prompt}
            # Original Article/Document
            #{original_content}

            # Summary to Evaluate
            #{summary}
          PROMPT
        end

        def overall_score
          parsed_response["overall"]["score"] if completed?
        end

        def overall_justification
          parsed_response["overall"]["justification"] if completed?
        end

        def coverage_score
          parsed_response["coverage"]["score"] if completed?
        end

        def coverage_justification
          parsed_response["coverage"]["justification"] if completed?
        end

        def accuracy_score
          parsed_response["accuracy"]["score"] if completed?
        end

        def accuracy_justification
          parsed_response["accuracy"]["justification"] if completed?
        end

        def clarity_score
          parsed_response["clarity"]["score"] if completed?
        end

        def clarity_justification
          parsed_response["clarity"]["justification"] if completed?
        end

        def conciseness_score
          parsed_response["conciseness"]["score"] if completed?
        end

        def conciseness_justification
          parsed_response["conciseness"]["justification"] if completed?
        end

      private

        def additional_context_prompt
          return if additional_context.blank?

          <<~PROMPT
            \n# Additional context:
            #{additional_context}
          PROMPT
        end
      end
    end
  end
end
