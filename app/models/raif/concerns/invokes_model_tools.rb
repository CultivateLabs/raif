# frozen_string_literal: true

module Raif::Concerns::InvokesModelTools
  extend ActiveSupport::Concern

  included do
    has_many :model_tool_invocations,
      class_name: "Raif::ModelToolInvocation",
      as: :source,
      dependent: :destroy
  end

  def available_model_tools_map
    @available_model_tools_map ||= available_model_tools&.map do |tool_name|
      tool_klass = tool_name.is_a?(String) ? tool_name.constantize : tool_name
      [tool_klass.tool_name, tool_klass]
    end.to_h
  end
end
