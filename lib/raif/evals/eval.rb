# frozen_string_literal: true

module Raif
  module Evals
    class Eval
      attr_reader :description, :expectation_results

      def initialize(description:)
        @description = description
        @expectation_results = []
      end

      def add_expectation_result(result)
        @expectation_results << result
      end

      def passed?
        expectation_results.all?(&:passed?)
      end

      def to_h
        {
          description: description,
          passed: passed?,
          expectation_results: expectation_results.map(&:to_h)
        }
      end
    end
  end
end
