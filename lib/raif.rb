# frozen_string_literal: true

require "raif/version"
require "raif/root"
require "raif/languages"
require "raif/engine"
require "raif/configuration"
require "raif/errors"
require "raif/llm"
require "raif/api_adapters/base"
require "raif/api_adapters/open_ai"
require "raif/api_adapters/bedrock"
require "raif/model_tool"
require "raif/model_response"
require "raif/utils"

require "faraday"
require "loofah"
require "openai"
require "pagy"
require "reverse_markdown"

module Raif
  class << self
    attr_accessor :configuration
    attr_accessor :llm_registry

    attr_writer :logger
  end

  def self.config
    @configuration ||= Raif::Configuration.new
  end

  def self.configure
    yield(config)
  end

  def self.logger
    @logger ||= Rails.logger
  end

  def self.register_llm(llm_config)
    llm = Raif::Llm.new(**llm_config)

    unless llm.valid?
      raise ArgumentError, "The LLM you tried to register is invalid: #{llm.errors.full_messages.join(", ")}"
    end

    @llm_registry ||= {}
    @llm_registry[llm.key] = llm
  end

  def self.llm_for_key(key)
    llm_registry[key]
  end

  def self.available_llms
    llm_registry.values
  end

  def self.available_llm_keys
    llm_registry.keys
  end
end
