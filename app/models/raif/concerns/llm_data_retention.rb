# frozen_string_literal: true

# Per-class override of the provider data retention settings. A nil class
# attribute (the default) defers to Raif.config, so a subclass opts out of the
# app-wide posture only by saying so explicitly:
#
#   class MyTask < Raif::Task
#     self.open_ai_store_responses = true
#   end
#
# Raif::Llm#chat takes the same three keyword arguments for a one-off override.
module Raif::Concerns::LlmDataRetention
  extend ActiveSupport::Concern

  included do
    class_attribute :open_ai_store_responses, instance_writer: false, default: nil
    class_attribute :open_router_data_collection, instance_writer: false, default: nil
    class_attribute :open_router_zdr, instance_writer: false, default: nil
  end
end
