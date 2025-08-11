# frozen_string_literal: true

module Raif
  module Evals
    class ExpectationResult
      attr_reader :description, :status, :error
      attr_accessor :metadata

      def initialize(description:, status:, error: nil, metadata: nil)
        @description = description
        @status = status
        @error = error
        @metadata = metadata
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
          error: error&.message,
          metadata: metadata
        }.compact
      end
    end
  end
end
