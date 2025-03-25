# frozen_string_literal: true

module Raif::Concerns::HasAvailableModelTools
  extend ActiveSupport::Concern

  def available_model_tools_map
    @available_model_tools_map ||= available_model_tools&.map do |tool_name|
      tool_klass = tool_name.is_a?(String) ? tool_name.constantize : tool_name
      [tool_klass.tool_name, tool_klass]
    end.to_h
  end

end
