# frozen_string_literal: true

module Raif
  module Evals
    # One input row of a Dataset. Eval sets only ever receive these - the dataset block
    # returns plain hashes and Raif builds the cases from them.
    class EvalCase
      attr_reader :id, :input, :expected

      def initialize(id:, input:, expected: nil)
        @id = id.to_s.freeze
        @input = input
        @expected = expected
        freeze
      end

      # Reading straight through to the input keeps the common case short:
      # eval_case["title"] rather than eval_case.input["title"].
      def [](key)
        input[key]
      end

      def to_h
        { id: id, input: input, expected: expected }.compact
      end
    end
  end
end
