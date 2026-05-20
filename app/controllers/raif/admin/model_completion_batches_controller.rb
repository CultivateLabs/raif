# frozen_string_literal: true

module Raif
  module Admin
    class ModelCompletionBatchesController < Raif::Admin::ApplicationController
      def index
        @selected_status = params[:status].presence || "all"
        @selected_llm_model_key = params[:llm_model_key].presence
        @selected_type = params[:type].presence

        @llm_model_keys = Raif::ModelCompletionBatch.distinct.order(:llm_model_key).pluck(:llm_model_key)
        @types = Raif::ModelCompletionBatch.distinct.order(:type).pluck(:type).compact

        batches = Raif::ModelCompletionBatch.order(created_at: :desc)

        if @selected_status != "all" && Raif::ModelCompletionBatch::STATUSES.include?(@selected_status)
          batches = batches.where(status: @selected_status)
        end

        batches = batches.where(llm_model_key: @selected_llm_model_key) if @selected_llm_model_key.present?
        batches = batches.where(type: @selected_type) if @selected_type.present?

        @pagy, @model_completion_batches = pagy(batches)

        @completion_counts_by_batch_id = Raif::ModelCompletion
          .where(raif_model_completion_batch_id: @model_completion_batches.map(&:id))
          .group(:raif_model_completion_batch_id)
          .count
      end

      def show
        @model_completion_batch = Raif::ModelCompletionBatch.find(params[:id])
        @model_completions = @model_completion_batch.raif_model_completions.order(:id).to_a
      end
    end
  end
end
