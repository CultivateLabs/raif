# frozen_string_literal: true

module Raif
  module ApplicationHelper
    include Pagy::Frontend

    def format_task_response(task)
      if task.response_format_json? && task.raw_response.present?
        JSON.pretty_generate(JSON.parse(task.raw_response))
      else
        task.raw_response
      end
    rescue JSON::ParserError
      task.raw_response
    end

    def pretty_json(value)
      JSON.pretty_generate(JSON.parse(value))
    rescue StandardError
      value
    end

    def llm_model_options(selected: nil)
      options = Raif.available_llm_keys.map do |key|
        label = I18n.t("raif.model_names.#{key}", default: key.to_s)
        [label, key.to_s]
      end.sort_by(&:first)

      options_for_select(options, selected&.to_s)
    end

    def llm_pricing_json
      pricing = {}
      Raif.available_llm_keys.each do |key|
        config = Raif.llm_config(key)
        next unless config

        pricing[key.to_s] = {
          input: config[:input_token_cost] || 0,
          output: config[:output_token_cost] || 0
        }
      end

      pricing.to_json
    end
  end
end
