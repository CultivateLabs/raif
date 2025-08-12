# frozen_string_literal: true

module Raif::Concerns::HasLlm
  extend ActiveSupport::Concern

  included do
    validates :llm_model_key, presence: true, inclusion: { in: ->{ Raif.available_llm_keys.map(&:to_s) } }

    before_validation ->{ self.llm_model_key ||= default_llm_model_key }
  end

  def default_llm_model_key
    Raif.config.default_llm_model_key
  end

  def llm
    @llm ||= Raif.llm(llm_model_key.to_sym)
  end
end
