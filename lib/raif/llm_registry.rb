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

    key = llm.key.to_sym
    @llm_registry ||= {}
    @llm_registry[key] = llm_config.merge(llm_class: llm_class, key: key)
  end

  def self.llm(model_key)
    llm_config = llm_registry[model_key&.to_sym]

    if llm_config.nil?
      raise ArgumentError, "No LLM found for model key: #{model_key}. Available models: #{available_llm_keys.join(", ")}"
    end

    llm_class = llm_config[:llm_class]
    llm = llm_class.new(**llm_config.except(:llm_class))
    warn_if_deprecated(llm)
    llm
  end

  def self.warn_if_deprecated(llm)
    return unless llm.deprecated?

    @deprecation_warnings_issued ||= {}
    return if @deprecation_warnings_issued[llm.key]

    @deprecation_warnings_issued[llm.key] = true
    Raif.logger.warn(llm.deprecation_message)
  end

  def self.reset_deprecation_warnings!
    @deprecation_warnings_issued = {}
  end

  def self.available_llms
    llm_registry.values
  end

  def self.available_llm_keys
    llm_registry.keys
  end

  def self.llm_config(model_key)
    llm_registry[model_key&.to_sym]
  end
end
