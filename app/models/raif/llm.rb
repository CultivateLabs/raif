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
      :output_token_cost,
      :supported_provider_managed_tools

    validates :key, presence: true
    validates :api_name, presence: true

    VALID_RESPONSE_FORMATS = [:text, :json, :html].freeze

    alias_method :supports_native_tool_use?, :supports_native_tool_use

    def initialize(
      key:,
      api_name:,
      model_provider_settings: {},
      supported_provider_managed_tools: [],
      supports_native_tool_use: true,
      temperature: nil,
      max_completion_tokens: nil,
      input_token_cost: nil,
      output_token_cost: nil
    )
      @key = key
      @api_name = api_name
      @provider_settings = model_provider_settings
      @supports_native_tool_use = supports_native_tool_use
      @default_temperature = temperature || 0.7
      @default_max_completion_tokens = max_completion_tokens
      @input_token_cost = input_token_cost
      @output_token_cost = output_token_cost
      @supported_provider_managed_tools = supported_provider_managed_tools.map(&:to_s)
    end

    def name
      I18n.t("raif.model_names.#{key}")
    end

    def chat(message: nil, messages: nil, response_format: :text, available_model_tools: [], source: nil, system_prompt: nil, temperature: nil,
      max_completion_tokens: nil, tool_choice: nil, &block)
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

      if tool_choice.present? && !available_model_tools.map(&:to_s).include?(tool_choice.to_s)
        raise ArgumentError,
          "Raif::Llm#chat - Invalid tool choice: #{tool_choice} is not included in the available model tools: #{available_model_tools.join(", ")}"
      end

      unless Raif.config.llm_api_requests_enabled
        Raif.logger.warn("LLM API requests are disabled. Skipping request to #{api_name}.")
        return
      end

      messages = [{ "role" => "user", "content" => message }] if message.present?

      temperature ||= default_temperature
      max_completion_tokens ||= default_max_completion_tokens

      model_completion = Raif::ModelCompletion.create!(
        messages: format_messages(messages),
        system_prompt: system_prompt,
        response_format: response_format,
        source: source,
        llm_model_key: key.to_s,
        model_api_name: api_name,
        temperature: temperature,
        max_completion_tokens: max_completion_tokens,
        available_model_tools: available_model_tools,
        tool_choice: tool_choice&.to_s,
        stream_response: block_given?
      )

      retry_with_backoff(model_completion) do
        perform_model_completion!(model_completion, &block)
      end

      model_completion.completed!
      model_completion
    rescue Raif::Errors::StreamingError => e
      Rails.logger.error("Raif streaming error -- code: #{e.code} -- type: #{e.type} -- message: #{e.message} -- event: #{e.event}")
      model_completion&.record_failure!(e)
      raise e
    rescue Faraday::Error => e
      Raif.logger.error("LLM API request failed (status: #{e.response_status}): #{e.message}")
      Raif.logger.error(e.response_body)
      model_completion&.record_failure!(e)
      raise e
    rescue StandardError => e
      model_completion&.record_failure!(e)
      raise e
    end

    def perform_model_completion!(model_completion, &block)
      raise NotImplementedError, "#{self.class.name} must implement #perform_model_completion!"
    end

    def self.valid_response_formats
      VALID_RESPONSE_FORMATS
    end

    def supports_provider_managed_tool?(tool_klass)
      supported_provider_managed_tools&.include?(tool_klass.to_s)
    end

    # Build the tool_choice parameter to force a specific tool to be called.
    # Each provider implements this to return the correct format.
    # @param tool_name [String] The name of the tool to force
    # @return [Hash] The tool_choice parameter for the provider's API
    def build_forced_tool_choice(tool_name)
      raise NotImplementedError, "#{self.class.name} must implement #build_forced_tool_choice"
    end

    def validate_provider_managed_tool_support!(tool)
      unless supports_provider_managed_tool?(tool)
        raise Raif::Errors::UnsupportedFeatureError,
          "Invalid provider-managed tool: #{tool.name} for #{key}"
      end
    end

  private

    def retry_with_backoff(model_completion)
      retries = 0
      max_retries = Raif.config.llm_request_max_retries
      base_delay = 3
      max_delay = 30

      begin
        yield
      rescue *Raif.config.llm_request_retriable_exceptions => e
        retries += 1
        if retries <= max_retries
          delay = [base_delay * (2**(retries - 1)), max_delay].min
          Raif.logger.warn("Retrying LLM API request after error: #{e.message}. Attempt #{retries}/#{max_retries}. Waiting #{delay} seconds...")
          model_completion.increment!(:retry_count)
          sleep delay
          retry
        else
          Raif.logger.error("LLM API request failed after #{max_retries} retries. Last error: #{e.message}")
          raise
        end
      end
    end

    def streaming_response_type
      raise NotImplementedError, "#{self.class.name} must implement #streaming_response_type"
    end

    def streaming_chunk_handler(model_completion, &block)
      return unless model_completion.stream_response?

      streaming_response = streaming_response_type.new
      event_parser = EventStreamParser::Parser.new
      accumulated_delta = ""

      proc do |chunk, _size, _env|
        event_parser.feed(chunk) do |event_type, data, _id, _reconnect_time|
          if data.blank? || data == "[DONE]"
            update_model_completion(model_completion, streaming_response.current_response_json)
            next
          end

          event_data = JSON.parse(data)
          delta, finish_reason = streaming_response.process_streaming_event(event_type, event_data)

          accumulated_delta += delta if delta.present?

          if accumulated_delta.length >= Raif.config.streaming_update_chunk_size_threshold || finish_reason.present?
            update_model_completion(model_completion, streaming_response.current_response_json)

            if accumulated_delta.present?
              block.call(model_completion, accumulated_delta, event_data)
              accumulated_delta = ""
            end
          end
        end
      end
    end

  end
end
