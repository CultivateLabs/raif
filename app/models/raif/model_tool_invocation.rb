# frozen_string_literal: true

require "json-schema"

class Raif::ModelToolInvocation < Raif::ApplicationRecord
  belongs_to :raif_completion, class_name: "Raif::Completion"

  validates :tool_type, presence: true
  validate :ensure_valid_tool_argument_schema, if: -> { tool_arguments_schema.present? }

  delegate :tool_arguments_schema, :renderable?, :tool_name, to: :tool

  def tool
    @tool ||= tool_type.constantize.new
  end

  def to_partial_path
    "raif/model_tool_invocations/#{tool.invocation_partial_name}"
  end

  def ensure_valid_tool_argument_schema
    unless JSON::Validator.validate(tool_arguments_schema, tool_arguments)
      errors.add(:tool_arguments, "does not match schema")
    end
  end

end
