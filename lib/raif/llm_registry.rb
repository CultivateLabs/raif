# frozen_string_literal: true

module Raif
  def self.llm_registry
    @llm_registry ||= {}
  end

  def self.register_llm(llm_class, llm_config)
    llm = llm_class.new(**llm_config)

    unless llm.valid?
      raise ArgumentError, "The LLM you tried to register is invalid: #{llm.errors.full_messages.join(", ")}"
    end

    @llm_registry ||= {}
    @llm_registry[llm.key] = llm_config.merge(llm_class: llm_class)
  end

  def self.llm(model_key)
    llm_config = llm_registry[model_key]

    if llm_config.nil?
      raise ArgumentError, "No LLM found for model key: #{model_key}. Available models: #{available_llm_keys.join(", ")}"
    end

    llm_class = llm_config[:llm_class]
    llm_class.new(**llm_config.except(:llm_class))
  end

  def self.available_llms
    llm_registry.values
  end

  def self.available_llm_keys
    llm_registry.keys
  end

  def self.llm_config(model_key)
    llm_registry[model_key]
  end
end
