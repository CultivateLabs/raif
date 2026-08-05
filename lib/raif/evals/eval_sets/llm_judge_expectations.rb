# frozen_string_literal: true

module Raif
  module Evals
    module EvalSets
      module LlmJudgeExpectations

        # Uses an LLM judge to evaluate whether content meets specific criteria with a binary pass/fail result.
        #
        # This method leverages the Binary LLM judge to assess content against provided criteria,
        # returning a pass or fail judgment with reasoning and confidence scores.
        #
        # @param content [String] The content to be evaluated by the LLM judge
        # @param criteria [String] The evaluation criteria that the content must meet
        # @param examples [Array<Hash>] Optional examples showing how to evaluate similar content.
        #   Each example should have keys: :content, :passes (boolean), :reasoning
        # @param strict [Boolean] Whether to apply criteria strictly (true) or with reasonable judgment (false)
        # @param llm_judge_model_key [Symbol, nil] Optional specific LLM model to use for judging.
        #   If nil, uses the configured default judge model or falls back to default LLM
        # @param additional_context [String, nil] Optional additional context to be provided to the judge
        # @param judge_attributes [Hash] Optional attributes merged into the judge task on top of
        #   the eval set's #judge_task_attributes
        # @param label [String, nil] Optional explicit description for the expectation, for when the
        #   criteria is too long to read well as one
        #
        # @return [ExpectationResult] Result object containing pass/fail status and judge metadata
        #
        # @example Basic usage
        #   expect_llm_judge_passes(
        #     task.parsed_response,
        #     criteria: "Response is polite and professional"
        #   )
        #
        # @example With examples and strict mode
        #   expect_llm_judge_passes(
        #     content,
        #     criteria: "Contains a proper greeting",
        #     examples: [
        #       { content: "Hello, how can I help?", passes: true, reasoning: "Contains greeting" },
        #       { content: "What do you want?", passes: false, reasoning: "No greeting, rude tone" }
        #     ],
        #     strict: true
        #   )
        #
        # @note The judge result includes metadata accessible via expectation_result.metadata:
        #   - :passes - Boolean result
        #   - :reasoning - Detailed explanation
        #   - :confidence - Confidence score (0.0-1.0)
        def expect_llm_judge_passes(content, criteria:, examples: [], strict: false, llm_judge_model_key: nil, additional_context: nil,
          result_metadata: {}, judge_attributes: {}, label: nil)
          judge_task = LlmJudges::Binary.run(
            content_to_judge: content,
            criteria: criteria,
            examples: examples,
            strict_mode: strict,
            llm_model_key: llm_judge_model_key,
            additional_context: additional_context,
            **resolved_judge_attributes(judge_attributes)
          )

          if judge_task.low_confidence? && output.respond_to?(:puts)
            output.puts Raif::Utils::Colors.yellow("    ⚠ Low confidence: #{judge_task.judgment_confidence}")
          end

          if Raif.config.evals_verbose_output && output.respond_to?(:puts)
            output.puts "    #{judge_task.judgment_reasoning}"
          end

          judge_metadata = {
            passes: judge_task.passes?,
            reasoning: judge_task.judgment_reasoning,
            confidence: judge_task.judgment_confidence,
          }.compact

          # Merge user metadata with judge metadata
          combined_metadata = result_metadata.merge(judge_metadata)

          expectation_result = expect label || "LLM judge: #{criteria}", result_metadata: combined_metadata do
            judge_task.passes?
          end

          if expectation_result && judge_task.errors.any?
            expectation_result.error_message = judge_task.errors.full_messages.join(", ")
          end

          expectation_result
        end

        # Uses an LLM judge to evaluate content with a numerical score based on a detailed rubric.
        #
        # This method leverages the Scored LLM judge to assess content against a scoring rubric,
        # providing a numerical score with detailed reasoning and determining pass/fail based on
        # the minimum passing score threshold.
        #
        # As well as the pass/fail expectation, the judge's score is recorded as a first-class
        # score named after the rubric, so it lands in the run's score summaries and can be
        # compared across runs.
        #
        # @param content [String] The content to be evaluated by the LLM judge
        # @param scoring_rubric [ScoringRubric, String] The rubric to use for scoring. Can be a
        #   ScoringRubric object with structured levels or a plain string description
        # @param min_passing_score [Integer] Minimum score required to pass
        # @param llm_judge_model_key [Symbol, nil] Optional specific LLM model to use for judging.
        #   If nil, uses the configured default judge model or falls back to default LLM
        # @param additional_context [String, nil] Optional additional context to be provided to the judge
        # @param judge_attributes [Hash] Optional attributes merged into the judge task on top of
        #   the eval set's #judge_task_attributes
        # @param label [String, nil] Optional explicit description for the expectation
        # @param score_name [String, Symbol, nil] Optional name for the recorded score, defaulting
        #   to the rubric's name. Needed when one eval judges two things against the same rubric
        #   and you want them tracked apart
        #
        # @return [ExpectationResult] Result object containing pass/fail status and judge metadata
        #
        # @example Using a built-in rubric
        #   expect_llm_judge_score(
        #     task.parsed_response,
        #     scoring_rubric: ScoringRubric.accuracy,
        #     min_passing_score: 8
        #   )
        #
        # @example Using a custom rubric
        #   rubric = ScoringRubric.new(
        #     name: :technical_writing,
        #     description: "Evaluates technical writing quality",
        #     levels: [
        #       { score_range: (9..10), description: "Expert-level technical content" },
        #       { score_range: (7..8), description: "Strong technical content" },
        #       { score_range: (5..6), description: "Adequate technical content" },
        #       { score_range: (3..4), description: "Weak technical content" },
        #       { score_range: (0..2), description: "Poor technical content" }
        #     ]
        #   )
        #   expect_llm_judge_score(output, scoring_rubric: rubric, min_passing_score: 7)
        #
        # @example Using a simple string rubric
        #   expect_llm_judge_score(
        #     output,
        #     scoring_rubric: "Rate clarity from 0-5 where 5 is crystal clear",
        #     min_passing_score: 4
        #   )
        #
        # @note The judge result includes metadata accessible via expectation_result.metadata:
        #   - :score - Numerical score given
        #   - :reasoning - Detailed explanation
        #   - :confidence - Confidence score (0.0-1.0)
        def expect_llm_judge_score(content, scoring_rubric:, min_passing_score:, llm_judge_model_key: nil, additional_context: nil,
          result_metadata: {}, judge_attributes: {}, label: nil, score_name: nil)
          scoring_rubric_obj = scoring_rubric

          judge_task = LlmJudges::Scored.run(
            content_to_judge: content,
            scoring_rubric: scoring_rubric_obj,
            llm_model_key: llm_judge_model_key,
            additional_context: additional_context,
            **resolved_judge_attributes(judge_attributes)
          )

          rubric_name = scoring_rubric_obj.respond_to?(:name) ? scoring_rubric_obj.name : "custom"
          output.puts "    Score: #{judge_task.judgment_score}"
          output.puts "    #{judge_task.judgment_reasoning}" if Raif.config.evals_verbose_output

          judge_metadata = {
            score: judge_task.judgment_score,
            reasoning: judge_task.judgment_reasoning,
            confidence: judge_task.judgment_confidence,
          }.compact

          # Merge user metadata with judge metadata
          combined_metadata = result_metadata.merge(judge_metadata)

          # The score is recorded directly rather than through #score, because the gating
          # expectation below has to keep its historical description: evals:compare matches
          # a result to its counterpart in an earlier run on that description.
          if judge_task.judgment_score
            current_eval_result.add_score(
              ScoreResult.new(
                name: score_name || rubric_name,
                value: judge_task.judgment_score,
                scale: (scoring_rubric_obj.scale if scoring_rubric_obj.respond_to?(:scale)),
                min: min_passing_score
              )
            )
          end

          expectation_result = expect label || "LLM judge score (#{rubric_name}): >= #{min_passing_score}",
            result_metadata: combined_metadata do
            judge_task.completed? && judge_task.judgment_score && judge_task.judgment_score >= min_passing_score
          end

          if expectation_result && judge_task.errors.any?
            expectation_result.error_message = judge_task.errors.full_messages.join(", ")
          end

          expectation_result
        end

        # Uses an LLM judge to compare two pieces of content and determine which better meets specified criteria.
        #
        # This method leverages the Comparative LLM judge to perform A/B testing between two pieces
        # of content. Content placement is randomized to avoid position bias, and the judge determines
        # which content better satisfies the comparison criteria.
        #
        # @param content_to_judge [String] The primary content being evaluated (will be randomly assigned to position A or B)
        # @param over [String] The comparison content to evaluate against (will be randomly assigned to position A or B)
        # @param criteria [String] The comparison criteria to use for evaluation
        # @param allow_ties [Boolean] Whether the judge can declare a tie if both contents are equal (default: true)
        # @param llm_judge_model_key [Symbol, nil] Optional specific LLM model to use for judging.
        #   If nil, uses the configured default judge model or falls back to default LLM
        # @param additional_context [String, nil] Optional additional context to help the judge
        #
        # @return [ExpectationResult] Result object containing pass/fail status and judge metadata
        #
        # @example Basic A/B comparison
        #   expect_llm_judge_prefers(
        #     new_response,
        #     over: baseline_response,
        #     criteria: "More comprehensive and accurate response"
        #   )
        #
        # @example Model comparison with no ties allowed
        #   expect_llm_judge_prefers(
        #     claude_response,
        #     over: gpt_response,
        #     criteria: "Better follows the specific instructions given",
        #     allow_ties: false
        #   )
        #
        # @example With additional context
        #   expect_llm_judge_prefers(
        #     response_a,
        #     over: response_b,
        #     criteria: "More helpful for a beginner audience",
        #     additional_context: "The user identified themselves as new to programming"
        #   )
        #
        # @note The expectation passes if the judge correctly identifies the expected winner.
        #   Due to randomization, content_to_judge may be assigned to either position A or B,
        #   and the judge's choice is validated against the expected winner.
        #
        # @note The judge result includes metadata accessible via expectation_result.metadata:
        #   - :winner - Which content won ("A", "B", or "tie")
        #   - :reasoning - Detailed explanation of the choice
        #   - :confidence - Confidence score (0.0-1.0)
        def expect_llm_judge_prefers(content_to_judge, over:, criteria:, allow_ties: true, llm_judge_model_key: nil, additional_context: nil,
          result_metadata: {}, judge_attributes: {}, label: nil)
          judge_task = LlmJudges::Comparative.run(
            content_to_judge: content_to_judge,
            over_content: over,
            comparison_criteria: criteria,
            allow_ties: allow_ties,
            llm_model_key: llm_judge_model_key,
            additional_context: additional_context,
            **resolved_judge_attributes(judge_attributes)
          )

          if output.respond_to?(:puts)
            output.puts "    Winner: #{judge_task.winner}"
            output.puts "    #{judge_task.judgment_reasoning}" if Raif.config.evals_verbose_output
          end

          judge_metadata = {
            winner: judge_task.winner,
            reasoning: judge_task.judgment_reasoning,
            confidence: judge_task.judgment_confidence,
          }.compact

          # Merge user metadata with judge metadata
          combined_metadata = result_metadata.merge(judge_metadata)

          expectation_result = expect label || "LLM judge prefers A over B: #{criteria}", result_metadata: combined_metadata do
            judge_task.completed? && judge_task.correct_expected_winner?
          end

          if expectation_result && judge_task.errors.any?
            expectation_result.error_message = judge_task.errors.full_messages.join(", ")
          end

          expectation_result
        end

      private

        # Raif::Evals::LlmJudge inherits from Raif::Task, so an app that has extended
        # Raif::Task with a required column needs those attributes on judge tasks too -
        # without them the judge's insert fails and takes the eval's transaction with it.
        def resolved_judge_attributes(judge_attributes)
          judge_task_attributes.merge(judge_attributes || {})
        end

      end
    end
  end
end
