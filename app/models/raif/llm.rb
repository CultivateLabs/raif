# frozen_string_literal: true

module Raif
  class Llm
    include ActiveModel::Model
    include Raif::Concerns::Llms::MessageFormatting

    attr_accessor :key,
      :api_name,
      :default_temperature,
      :default_max_completion_tokens,
      :supports_native_tool_use,
      :provider_settings,
      :input_token_cost,
      :output_token_cost

    validates :key, presence: true
    validates :api_name, presence: true

    VALID_RESPONSE_FORMATS = [:text, :json, :html].freeze

    alias_method :supports_native_tool_use?, :supports_native_tool_use

    def initialize(key:, api_name:, model_provider_settings: {}, supports_native_tool_use: true, temperature: nil, max_completion_tokens: nil,
      input_token_cost: nil, output_token_cost: nil)
      @key = key
      @api_name = api_name
      @provider_settings = model_provider_settings
      @supports_native_tool_use = supports_native_tool_use
      @default_temperature = temperature || 0.7
      @default_max_completion_tokens = max_completion_tokens
      @input_token_cost = input_token_cost
      @output_token_cost = output_token_cost
    end

    def name
      I18n.t("raif.model_names.#{key}")
    end

    def chat(message: nil, messages: nil, response_format: :text, available_model_tools: [], source: nil, system_prompt: nil, temperature: nil,
      max_completion_tokens: nil)
      unless response_format.is_a?(Symbol)
        raise ArgumentError,
          "Raif::Llm#chat - Invalid response format: #{response_format}. Must be a symbol (you passed #{response_format.class}) and be one of: #{VALID_RESPONSE_FORMATS.join(", ")}" # rubocop:disable Layout/LineLength
      end

      unless VALID_RESPONSE_FORMATS.include?(response_format)
        raise ArgumentError, "Raif::Llm#chat - Invalid response format: #{response_format}. Must be one of: #{VALID_RESPONSE_FORMATS.join(", ")}"
      end

      unless message.present? || messages.present?
        raise ArgumentError, "Raif::Llm#chat - You must provide either a message: or messages: argument"
      end

      if message.present? && messages.present?
        raise ArgumentError, "Raif::Llm#chat - You must provide either a message: or messages: argument, not both"
      end

      unless Raif.config.llm_api_requests_enabled
        Raif.logger.warn("LLM API requests are disabled. Skipping request to #{api_name}.")
        return
      end

      messages = [{ "role" => "user", "content" => message }] if message.present?

      temperature ||= default_temperature
      max_completion_tokens ||= default_max_completion_tokens

      model_completion = Raif::ModelCompletion.new(
        messages: format_messages(messages),
        system_prompt: system_prompt,
        response_format: response_format,
        source: source,
        llm_model_key: key.to_s,
        model_api_name: api_name,
        temperature: temperature,
        max_completion_tokens: max_completion_tokens,
        available_model_tools: available_model_tools
      )

      perform_model_completion!(model_completion)
      model_completion
    end

    def perform_model_completion!(model_completion)
      raise NotImplementedError, "#{self.class.name} must implement #perform_model_completion!"
    end

    def self.valid_response_formats
      VALID_RESPONSE_FORMATS
    end

  end
end
