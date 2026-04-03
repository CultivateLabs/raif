# frozen_string_literal: true

module Raif
  class TokenEstimator
    def self.available?
      !!defined?(::Tiktoken)
    end

    # Estimates the total token count for a prompt + system prompt combination.
    # Returns nil if tiktoken_ruby is not installed.
    def self.estimate_tokens(*texts)
      return unless available?

      encoder = ::Tiktoken.encoding_for_model("gpt-4")
      texts.compact.sum { |text| encoder.encode(text).length }
    end
  end
end
