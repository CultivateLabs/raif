# frozen_string_literal: true

module Raif::Concerns::InvokesModelTools
  extend ActiveSupport::Concern

  included do
    has_many :raif_model_tool_invocations,
      class_name: "Raif::ModelToolInvocation",
      as: :source,
      dependent: :destroy
  end

end
