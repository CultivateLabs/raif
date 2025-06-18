# frozen_string_literal: true

module Raif
  module Errors
    class StreamingError < StandardError
      attr_reader :message, :type, :code, :event

      def initialize(message:, type:, event:, code: nil)
        super

        @message = message
        @type = type
        @code = code
        @event = event
      end
    end
  end
end
