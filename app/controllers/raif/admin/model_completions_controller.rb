# frozen_string_literal: true

module Raif
  module Admin
    class ModelCompletionsController < Raif::Admin::ApplicationController
      include Pagy::Backend

      def index
        @selected_status = params[:status].present? ? params[:status].to_sym : :all

        model_completions = Raif::ModelCompletion.order(created_at: :desc)

        if @selected_status.present? && @selected_status != :all
          case @selected_status
          when :completed
            model_completions = model_completions.completed
          when :failed
            model_completions = model_completions.failed
          when :started
            model_completions = model_completions.started.where(completed_at: nil, failed_at: nil)
          when :pending
            model_completions = model_completions.where(started_at: nil)
          end
        end

        @pagy, @model_completions = pagy(model_completions)
      end

      def show
        @model_completion = Raif::ModelCompletion.find(params[:id])
      end
    end
  end
end
