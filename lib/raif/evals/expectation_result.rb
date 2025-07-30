# frozen_string_literal: true

module Raif
  module Evals
    class ExpectationResult
      attr_reader :description, :status, :error

      def initialize(description:, status:, error: nil)
        @description = description
        @status = status
        @error = error
      end

      def passed?
        @status == :passed
      end

      def failed?
        @status == :failed
      end

      def error?
        @status == :error
      end

      def to_h
        {
          description: description,
          status: status,
          error: error&.message
        }.compact
      end
    end
  end
end
