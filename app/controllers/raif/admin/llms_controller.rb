# frozen_string_literal: true

module Raif
  module Admin
    class LlmsController < Raif::Admin::ApplicationController

      def index
        @llms = Raif.llm_registry.map do |_key, config|
          llm_class = config[:llm_class]
          llm_class.new(**config.except(:llm_class))
        end

        @llms.sort_by!(&:name)

        @provider_names = @llms.map { |llm| llm.class.name.demodulize }.uniq.sort
        @llm_names = @llms.map(&:name).sort

        @selected_providers = Array(params[:providers]).reject(&:blank?)
        @selected_names = Array(params[:names]).reject(&:blank?)

        @llms = @llms.select { |llm| @selected_providers.include?(llm.class.name.demodulize) } if @selected_providers.present?
        @llms = @llms.select { |llm| @selected_names.include?(llm.name) } if @selected_names.present?
      end

    end
  end
end
