# frozen_string_literal: true

module Raif
  class PromptStudioBatchRunItemJob < ApplicationJob

    def perform(item:)
      item.execute!
    end

  end
end
