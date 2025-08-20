# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completions
#
#  id                        :bigint           not null, primary key
#  available_model_tools     :jsonb            not null
#  citations                 :jsonb
#  completion_tokens         :integer
#  llm_model_key             :string           not null
#  max_completion_tokens     :integer
#  messages                  :jsonb            not null
#  model_api_name            :string           not null
#  output_token_cost         :decimal(10, 6)
#  prompt_token_cost         :decimal(10, 6)
#  prompt_tokens             :integer
#  raw_response              :text
#  response_array            :jsonb
#  response_format           :integer          default("text"), not null
#  response_format_parameter :string
#  response_tool_calls       :jsonb
#  retry_count               :integer          default(0), not null
#  source_type               :string
#  stream_response           :boolean          default(FALSE), not null
#  system_prompt             :text
#  temperature               :decimal(5, 3)
#  total_cost                :decimal(10, 6)
#  total_tokens              :integer
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  response_id               :string
#  source_id                 :bigint
#
# Indexes
#
#  index_raif_model_completions_on_created_at  (created_at)
#  index_raif_model_completions_on_source      (source_type,source_id)
#
class Raif::ModelCompletion < Raif::ApplicationRecord
  include Raif::Concerns::LlmResponseParsing
  include Raif::Concerns::HasAvailableModelTools

  belongs_to :source, polymorphic: true, optional: true

  validates :llm_model_key, presence: true, inclusion: { in: ->{ Raif.available_llm_keys.map(&:to_s) } }
  validates :model_api_name, presence: true

  delegate :json_response_schema, to: :source, allow_nil: true

  before_save :set_total_tokens
  before_save :calculate_costs

  after_initialize -> { self.messages ||= [] }
  after_initialize -> { self.available_model_tools ||= [] }
  after_initialize -> { self.response_array ||= [] }
  after_initialize -> { self.citations ||= [] }

  def json_response_schema
    source.json_response_schema if source&.respond_to?(:json_response_schema)
  end

  def set_total_tokens
    self.total_tokens ||= completion_tokens.present? && prompt_tokens.present? ? completion_tokens + prompt_tokens : nil
  end

  def calculate_costs
    if prompt_tokens.present? && llm_config[:input_token_cost].present?
      self.prompt_token_cost = llm_config[:input_token_cost] * prompt_tokens
    end

    if completion_tokens.present? && llm_config[:output_token_cost].present?
      self.output_token_cost = llm_config[:output_token_cost] * completion_tokens
    end

    if prompt_token_cost.present? || output_token_cost.present?
      self.total_cost = (prompt_token_cost || 0) + (output_token_cost || 0)
    end
  end

private

  def llm_config
    @llm_config ||= Raif.llm_config(llm_model_key.to_sym)
  end
end
