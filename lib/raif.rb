# frozen_string_literal: true

require "raif/version"
require "raif/languages"
require "raif/engine"
require "raif/configuration"
require "raif/errors"
require "raif/utils"
require "raif/llm_registry"
require "raif/embedding_model_registry"
require "raif/json_schema_builder"
require "raif/migration_checker"

require "faraday"
require "json-schema"
require "loofah"
require "pagy"
require "reverse_markdown"
require "turbo-rails"

module Raif
  class << self
    attr_accessor :configuration

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
end
