# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class BaseController < Raif::Admin::ApplicationController
        include Pagy::Backend

      private

        def build_prompt_comparison(record)
          Raif::PromptStudioComparisonBuilder.build(record)
        end

        helper_method :prompt_studio_runs_enabled?
        def prompt_studio_runs_enabled?
          Raif.config.prompt_studio_runs_enabled
        end
      end
    end
  end
end
