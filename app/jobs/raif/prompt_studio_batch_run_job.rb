# frozen_string_literal: true

module Raif
  class PromptStudioBatchRunJob < ApplicationJob

    def perform(batch_run:)
      batch_run.update!(started_at: Time.current)

      batch_run.items.where(status: "pending").find_each do |item|
        Raif::PromptStudioBatchRunItemJob.perform_later(item: item)
      end
    end

  end
end
