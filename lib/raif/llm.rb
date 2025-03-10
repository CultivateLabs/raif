# frozen_string_literal: true

module Raif
  class Llm
    include ActiveModel::Model

    attr_accessor :key, :api_name, :api_adapter, :response_format

    validates :key, presence: true
    validates :api_name, presence: true
    validates :api_adapter, presence: true

    VALID_RESPONSE_FORMATS = [:text, :json, :html].freeze

    def initialize(key:, api_name:, api_adapter:)
      @key = key
      @api_name = api_name
      @api_adapter = api_adapter.new(model_api_name: api_name)
    end

    def name
      I18n.t("raif.model_names.#{key}")
    end

    def chat(messages:, response_format: :text, system_prompt: nil)
      unless response_format.is_a?(Symbol)
        raise ArgumentError,
          "Raif::Llm#chat - Invalid response format: #{response_format}. Must be a symbol (you passed #{response_format.class}) and be one of: #{VALID_RESPONSE_FORMATS.join(", ")}" # rubocop:disable Layout/LineLength
      end

      unless VALID_RESPONSE_FORMATS.include?(response_format)
        raise ArgumentError, "Raif::Llm#chat - Invalid response format: #{response_format}. Must be one of: #{VALID_RESPONSE_FORMATS.join(", ")}"
      end

      unless Raif.config.llm_api_requests_enabled
        Raif.logger.warn("LLM API requests are disabled. Skipping request to #{adapter.model_api_name}.")
        return
      end

      @api_adapter.chat(messages: messages, system_prompt: system_prompt, response_format: response_format)
    end

    def self.valid_response_formats
      VALID_RESPONSE_FORMATS
    end
  end
end
