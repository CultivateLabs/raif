# frozen_string_literal: true

module Raif
  class Llm
    include ActiveModel::Model
    include Raif::Concerns::Llms::MessageFormatting

    attr_accessor :key,
      :api_name,
      :display_name,
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
      display_name: nil,
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
      @display_name = display_name
      @provider_settings = model_provider_settings
      @supports_native_tool_use = supports_native_tool_use
      @default_temperature = temperature || 0.7
      @default_max_completion_tokens = max_completion_tokens
      @input_token_cost = input_token_cost
      @output_token_cost = output_token_cost
      @supported_provider_managed_tools = supported_provider_managed_tools.map(&:to_s)
    end

    def name
      I18n.t("raif.model_names.#{key}", default: display_name || key.to_s.humanize)
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

      # Normalize :required / "required" to the symbol form for validation
      tool_choice = :required if tool_choice.to_s == "required"

      if tool_choice == :required
        if available_model_tools.blank?
          raise ArgumentError,
            "Raif::Llm#chat - tool_choice: :required requires at least one available model tool"
        end
      elsif tool_choice.present? && !available_model_tools.map(&:to_s).include?(tool_choice.to_s)
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

      model_completion.started!

      retry_with_backoff(model_completion) do
        perform_model_completion!(model_completion, &block)
        ensure_model_completion_present!(model_completion)
      end

      model_completion.completed!
      model_completion
    rescue Raif::Errors::StreamingError => e
      Rails.logger.error("Raif streaming error -- code: #{e.code} -- type: #{e.type} -- message: #{e.message} -- event: #{e.event}")
      model_completion&.record_failure!(e) unless model_completion&.failed?
      raise e
    rescue Faraday::Error => e
      Raif.logger.error("LLM API request failed (status: #{e.response_status}): #{e.message}")
      Raif.logger.error(e.response_body)
      model_completion&.record_failure!(e) unless model_completion&.failed?
      raise e
    rescue StandardError => e
      model_completion&.record_failure!(e) unless model_completion&.failed?
      raise e
    end

    def perform_model_completion!(model_completion, &block)
      raise NotImplementedError, "#{self.class.name} must implement #perform_model_completion!"
    end

    def self.valid_response_formats
      VALID_RESPONSE_FORMATS
    end

    # Override in subclasses to indicate whether prompt_tokens reported by the
    # provider already include cached tokens as a subset (OpenAI, Google,
    # OpenRouter) or whether cached tokens are reported separately and are
    # additive to prompt_tokens (Anthropic, Bedrock).
    def self.prompt_tokens_include_cached_tokens?
      true
    end

    # Multiplier applied to the base input_token_cost to derive the per-token
    # cost for cache reads.  Return nil when the provider has no cache pricing.
    def self.cache_read_input_token_cost_multiplier
      nil
    end

    # Multiplier applied to the base input_token_cost to derive the per-token
    # cost for cache creation writes.  Return nil when there is no write surcharge.
    def self.cache_creation_input_token_cost_multiplier
      nil
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

    # Build the tool_choice parameter to require the model to call any tool (but not a specific one).
    # Each provider implements this to return the correct format.
    # @return [Hash, String] The tool_choice parameter for the provider's API
    def build_required_tool_choice
      raise NotImplementedError, "#{self.class.name} must implement #build_required_tool_choice"
    end

    # Whether the provider can faithfully enforce tool_choice: :required for
    # the given tool set. Override in subclasses when a provider can only
    # enforce required tool use for some tool types.
    def supports_faithful_required_tool_choice?(available_model_tools)
      available_model_tools.present?
    end

    def validate_provider_managed_tool_support!(tool)
      unless supports_provider_managed_tool?(tool)
        raise Raif::Errors::UnsupportedFeatureError,
          "Invalid provider-managed tool: #{tool.name} for #{key}"
      end
    end

  private

    def retriable_exceptions
      Raif.config.llm_request_retriable_exceptions
    end

    def retry_with_backoff(model_completion)
      retries = 0
      max_retries = Raif.config.llm_request_max_retries
      base_delay = 3
      max_delay = 30

      begin
        yield
      rescue *retriable_exceptions => e
        retries += 1
        if retries <= max_retries
          delay = [base_delay * (2**(retries - 1)), max_delay].min
          log_retry(e, model_completion, retries, max_retries, delay)
          model_completion.increment!(:retry_count)
          sleep delay
          retry
        else
          Raif.logger.error("LLM API request failed after #{max_retries} retries. Last error: #{e.message}")
          raise
        end
      end
    end

    def log_retry(error, model_completion, attempt, max_retries, delay)
      if error.is_a?(Raif::Errors::BlankResponseError)
        has_reasoning = model_completion.response_array&.any? do |block|
          block.is_a?(Hash) ? block.key?("reasoning_content") : block.respond_to?(:reasoning_content)
        end
        Raif.logger.warn(
          "Blank response retry #{attempt}/#{max_retries} for #{api_name} " \
            "(ModelCompletion##{model_completion.id}, source: #{model_completion.source_type}##{model_completion.source_id}, " \
            "completion_tokens: #{model_completion.completion_tokens}, reasoning_content_present: #{has_reasoning}). " \
            "Waiting #{delay} seconds..."
        )
      else
        Raif.logger.warn("Retrying LLM API request after error: #{error.message}. Attempt #{attempt}/#{max_retries}. Waiting #{delay} seconds...")
      end
    end

    def streaming_response_type
      raise NotImplementedError, "#{self.class.name} must implement #streaming_response_type"
    end

    def ensure_model_completion_present!(model_completion)
      # response_array/raw provider data may still be present for debugging even when
      # the normalized response has no text or tool calls.
      return if model_completion.raw_response.present? || model_completion.response_tool_calls.present?

      raise Raif::Errors::BlankResponseError,
        "Model completion #{model_completion.id} returned no text response and no tool calls"
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
