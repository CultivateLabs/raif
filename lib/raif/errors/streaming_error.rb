# frozen_string_literal: true

module Raif
  module Errors
    class StreamingError < StandardError
      attr_reader :type, :code, :event

      def initialize(message:, type:, event:, code: nil)
        super(message)

        @type = type
        @code = code
        @event = event
      end

      def to_s
        "[#{type}] #{super} (code=#{code}, event=#{event})"
      end
    end
  end
end
