# frozen_string_literal: true

module Raif
  module Evals
    # One `eval "..." do ... end` declaration: the block, what it is called, and the dataset it
    # runs over. The definition, not the outcome - running one of these once against one case
    # produces an EvalResult.
    #
    # index is the definition's position in its eval set, assigned when it registers. Results are
    # grouped by it when repeats are collapsed into a pass rate, since descriptions are not unique.
    class EvalDefinition
      attr_reader :description, :block, :dataset, :index, :file, :line_number

      def initialize(description:, block:, index:, dataset: nil, file: nil, line_number: nil)
        @description = description
        @block = block
        @dataset = dataset
        @index = index
        @file = file
        @line_number = line_number
      end

      def dataset?
        !dataset.nil?
      end
    end
  end
end
