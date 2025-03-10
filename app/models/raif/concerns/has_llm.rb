# frozen_string_literal: true

module Raif::Concerns::HasLlm
  extend ActiveSupport::Concern

  included do
    validates :llm_model_name, presence: true, inclusion: { in: Raif.available_llm_keys.map(&:to_s) }

    before_validation ->{ self.llm_model_name ||= default_llm_model_name }
  end

  def default_llm_model_name
    Raif.config.default_llm_model_name
  end

  def llm
    @llm ||= Raif.llm_for_key(llm_model_name.to_sym)
  end
end
