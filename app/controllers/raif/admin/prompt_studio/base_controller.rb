# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class BaseController < Raif::Admin::ApplicationController
        include Pagy::Backend

      private

        # Attempts to rebuild the prompt from current code for a given record.
        # Returns a hash with the rendered prompts and any warnings.
        def build_prompt_comparison(record)
          warnings = []
          current_prompt = nil
          current_system_prompt = nil

          begin
            current_prompt = record.build_prompt
          rescue NotImplementedError
            # No prompt defined (expected for conversations/agents)
          rescue => e
            warnings << "Error rendering current prompt: #{e.message}"
          end

          begin
            current_system_prompt = record.build_system_prompt
          rescue NotImplementedError
            # No system prompt defined
          rescue => e
            warnings << "Error rendering current system prompt: #{e.message}"
          end

          # Check for stale GlobalID references in run_with
          if record.respond_to?(:run_with) && record.run_with.present?
            record.run_with.each do |_key, value|
              if value.is_a?(String) && value.start_with?("gid://")
                begin
                  GlobalID::Locator.locate(value)
                rescue ActiveRecord::RecordNotFound
                  warnings << I18n.t("raif.admin.prompt_studio.common.warning_stale_reference")
                  break
                end
              end
            end
          end

          original_prompt = record.respond_to?(:prompt) ? record.prompt : nil
          original_system_prompt = record.system_prompt

          {
            original_prompt: original_prompt,
            original_system_prompt: original_system_prompt,
            current_prompt: current_prompt,
            current_system_prompt: current_system_prompt,
            prompt_changed: original_prompt.present? && current_prompt.present? && original_prompt.strip != current_prompt.strip,
            system_prompt_changed: original_system_prompt.present? && current_system_prompt.present? && original_system_prompt.strip != current_system_prompt.strip,
            warnings: warnings
          }
        end

        helper_method :prompt_studio_runs_enabled?
        def prompt_studio_runs_enabled?
          Raif.config.prompt_studio_runs_enabled
        end
      end
    end
  end
end
