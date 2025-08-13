# frozen_string_literal: true

module Raif
  module Evals
    # ScoringRubric provides a standardized way to define evaluation criteria with
    # multiple scoring levels. Each level can define either a score range or a single
    # score value, along with descriptive text explaining what qualifies for that score.
    #
    # @example Creating a custom rubric
    #   rubric = ScoringRubric.new(
    #     name: :technical_accuracy,
    #     description: "Evaluates technical correctness and precision",
    #     levels: [
    #       { score_range: (9..10), description: "Technically perfect with no errors" },
    #       { score_range: (7..8), description: "Mostly correct with minor technical issues" },
    #       { score_range: (5..6), description: "Generally correct but some technical problems" },
    #       { score_range: (3..4), description: "Significant technical errors present" },
    #       { score_range: (0..2), description: "Technically incorrect or misleading" }
    #     ]
    #   )
    #
    # @example Integer scoring levels
    #   rubric = ScoringRubric.new(
    #     name: :technical_accuracy ,
    #     description: "Evaluates technical correctness and precision",
    #     levels: [
    #       { score: 5, description: "Technically perfect with no errors" },
    #       { score: 4, description: "Mostly correct with minor technical issues" },
    #       { score: 3, description: "Generally correct but some technical problems" },
    #       { score: 2, description: "Significant technical errors present" },
    #       { score: 1, description: "Mostly incorrect or misleading" },
    #       { score: 0, description: "Completely incorrect or misleading" }
    #     ]
    #   )
    #
    # @example Using built-in rubrics
    #   accuracy_rubric = ScoringRubric.accuracy
    #   helpfulness_rubric = ScoringRubric.helpfulness
    #   clarity_rubric = ScoringRubric.clarity
    #
    class ScoringRubric
      # @return [Symbol] The rubric's identifier name
      attr_reader :name
      # @return [String] Human-readable description of what this rubric evaluates
      attr_reader :description
      # @return [Array<Hash>] Array of scoring level definitions
      attr_reader :levels

      # Creates a new ScoringRubric with the specified criteria.
      #
      # @param name [Symbol] Identifier for this rubric (e.g., :accuracy, :helpfulness)
      # @param description [String] Human-readable description of what this rubric evaluates
      # @param levels [Array<Hash>] Array of scoring level definitions. Each level must contain
      #   either :score (Integer) or :score_range (Range), plus :description (String)
      def initialize(name:, description:, levels:)
        @name = name
        @description = description
        @levels = levels
      end

      # Converts the rubric into a formatted string suitable for LLM prompts.
      #
      # The output includes the rubric description followed by a detailed breakdown
      # of all scoring levels with their criteria.
      #
      # @return [String] Formatted rubric text ready for inclusion in prompts
      #
      # @example Output format
      #   "Evaluates factual correctness and precision
      #
      #   Scoring levels:
      #   - 9-10: Completely accurate with no errors
      #   - 7-8: Mostly accurate with minor imprecisions
      #   - 5-6: Generally accurate but some notable errors"
      #
      # @raise [ArgumentError] If a level doesn't contain :score or :score_range
      def to_prompt
        prompt = "#{description}\n\nScoring levels:\n"

        levels.each do |level|
          if level.key?(:score)
            score = level[:score]
            prompt += "- #{score}: #{level[:description]}\n"
          else
            range = level[:score_range]
            min, max = case range
            when Range
              [range.begin, range.exclude_end? ? range.end - 1 : range.end]
            else
              raise ArgumentError, "level must include :score or :score_range (Range)"
            end
            prompt += "- #{min}-#{max}: #{level[:description]}\n"
          end
        end

        prompt.strip
      end

      class << self
        # Creates a rubric for evaluating factual accuracy and correctness.
        #
        # This rubric focuses on whether information is factually correct,
        # precise, and free from errors or misconceptions.
        #
        # @return [ScoringRubric] Pre-configured accuracy rubric (1-5 scale)
        #
        # @example
        #   rubric = ScoringRubric.accuracy
        #   expect_llm_judge_score(response, scoring_rubric: rubric, min_passing_score: 4)
        def accuracy
          new(
            name: :accuracy,
            description: "Evaluates factual correctness and precision",
            levels: [
              { score: 5, description: "Completely accurate with no errors" },
              { score: 4, description: "Mostly accurate with minor imprecisions" },
              { score: 3, description: "Generally accurate but some notable errors" },
              { score: 2, description: "Significant inaccuracies present" },
              { score: 1, description: "Mostly or entirely inaccurate" }
            ]
          )
        end

        # Creates a rubric for evaluating how well content addresses user needs.
        #
        # This rubric assesses whether the response is useful, relevant, and
        # effectively helps the user accomplish their goals.
        #
        # @return [ScoringRubric] Pre-configured helpfulness rubric (1-5 scale)
        #
        # @example
        #   rubric = ScoringRubric.helpfulness
        #   expect_llm_judge_score(response, scoring_rubric: rubric, min_passing_score: 4)
        def helpfulness
          new(
            name: :helpfulness,
            description: "Evaluates how well the response addresses user needs",
            levels: [
              { score: 5, description: "Extremely helpful, fully addresses the need" },
              { score: 4, description: "Very helpful with good coverage" },
              { score: 3, description: "Moderately helpful but missing some aspects" },
              { score: 2, description: "Somewhat helpful but significant gaps" },
              { score: 1, description: "Not helpful or misleading" }
            ]
          )
        end

        # Creates a rubric for evaluating clarity and comprehensibility.
        #
        # This rubric focuses on how easy content is to understand, whether
        # it's well-organized, and if the language is appropriate for the audience.
        #
        # @return [ScoringRubric] Pre-configured clarity rubric (1-5 scale)
        #
        # @example
        #   rubric = ScoringRubric.clarity
        #   expect_llm_judge_score(response, scoring_rubric: rubric, min_passing_score: 4)
        def clarity
          new(
            name: :clarity,
            description: "Evaluates clarity and comprehensibility",
            levels: [
              { score: 5, description: "Crystal clear and easy to understand" },
              { score: 4, description: "Clear with minor ambiguities" },
              { score: 3, description: "Generally clear but some confusion" },
              { score: 2, description: "Unclear in significant ways" },
              { score: 1, description: "Very unclear or incomprehensible" }
            ]
          )
        end
      end
    end
  end
end
