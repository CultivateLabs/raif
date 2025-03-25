# frozen_string_literal: true

class Raif::ModelCompletion < Raif::ApplicationRecord
  include Raif::Concerns::LlmResponseParsing
  include Raif::Concerns::HasAvailableModelTools

  belongs_to :source, polymorphic: true, optional: true

  validates :llm_model_key, presence: true, inclusion: { in: ->{ Raif.available_llm_keys.map(&:to_s) } }
  validates :model_api_name, presence: true

  delegate :json_response_schema, to: :source, allow_nil: true

  before_save :set_total_tokens

  after_initialize -> { self.messages ||= [] }
  after_initialize -> { self.available_model_tools ||= [] }

  def json_response_schema
    source.json_response_schema if source&.respond_to?(:json_response_schema)
  end

protected

  def set_total_tokens
    self.total_tokens ||= completion_tokens.present? && prompt_tokens.present? ? completion_tokens + prompt_tokens : nil
  end
end
