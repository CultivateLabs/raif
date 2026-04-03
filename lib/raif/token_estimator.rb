# frozen_string_literal: true

module Raif
  class TokenEstimator
    def self.available?
      return true if defined?(::Tiktoken)

      require "tiktoken_ruby"
      !!defined?(::Tiktoken)
    rescue LoadError
      false
    end

    # Estimates the total token count for a prompt + system prompt combination.
    # Returns nil if tiktoken_ruby is not installed.
    def self.estimate_tokens(*texts)
      return unless available?

      encoder = encoder_for_model("gpt-4")
      texts.compact.sum { |text| encoder.encode(text).length }
    end

    def self.encoder_for_model(model)
      @encoders ||= {}
      @encoders[model] ||= ::Tiktoken.encoding_for_model(model)
    end
  end
end
