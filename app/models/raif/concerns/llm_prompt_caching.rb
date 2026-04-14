# frozen_string_literal: true

module Raif::Concerns::LlmPromptCaching
  extend ActiveSupport::Concern

  included do
    class_attribute :anthropic_prompt_caching_enabled, instance_writer: false, default: false
    class_attribute :bedrock_prompt_caching_enabled, instance_writer: false, default: false
  end

  class_methods do
    def enable_anthropic_prompt_caching
      self.anthropic_prompt_caching_enabled = true
    end

    def enable_bedrock_prompt_caching
      self.bedrock_prompt_caching_enabled = true
    end
  end
end
