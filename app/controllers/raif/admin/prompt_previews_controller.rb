# frozen_string_literal: true

module Raif
  module Admin
    class PromptPreviewsController < Raif::Admin::ApplicationController
      def index
        @previews = Raif::PromptPreview.all
      end

      def show
        @preview_class = find_preview_class
        @method_name = params[:method_name]

        unless @preview_class && @method_name.present? && @preview_class.preview_methods.include?(@method_name.to_sym)
          redirect_to raif.admin_prompt_previews_path, alert: "Preview not found"
          return
        end

        @result = @preview_class.render_preview(@method_name)
      end

    private

      def find_preview_class
        return unless params[:id].present?

        Raif::PromptPreview.find_by_preview_id(params[:id])
      end
    end
  end
end
