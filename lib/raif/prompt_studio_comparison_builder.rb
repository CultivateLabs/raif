# frozen_string_literal: true

module Raif
  class PromptStudioComparisonBuilder
    # Attempts to rebuild the prompt from current code for a given record.
    # Returns a hash with the rendered prompts and any warnings.
    def self.build(record)
      new(record).build
    end

    def initialize(record)
      @record = record
    end

    def build
      {
        original_prompt: original_prompt,
        original_system_prompt: original_system_prompt,
        current_prompt: current_prompt,
        current_system_prompt: current_system_prompt,
        prompt_changed: changed?(original_prompt, current_prompt),
        system_prompt_changed: changed?(original_system_prompt, current_system_prompt),
        has_stale_references: has_stale_references?,
        warnings: warnings
      }
    end

  private

    def original_prompt
      @original_prompt ||= @record.respond_to?(:prompt) ? @record.prompt : nil
    end

    def original_system_prompt
      @original_system_prompt ||= @record.system_prompt
    end

    def current_prompt
      return @current_prompt if defined?(@current_prompt)

      @current_prompt = begin
        @record.build_prompt
      rescue NotImplementedError
        nil
      rescue => e
        warnings << "Error rendering current prompt: #{e.message}"
        nil
      end
    end

    def current_system_prompt
      return @current_system_prompt if defined?(@current_system_prompt)

      @current_system_prompt = begin
        @record.build_system_prompt
      rescue NotImplementedError
        nil
      rescue => e
        warnings << "Error rendering current system prompt: #{e.message}"
        nil
      end
    end

    def warnings
      @warnings ||= [].tap do |w|
        w << I18n.t("raif.admin.prompt_studio.common.warning_stale_reference") if has_stale_references?
      end
    end

    def has_stale_references?
      return @has_stale_references if defined?(@has_stale_references)

      @has_stale_references = detect_stale_references
    end

    def detect_stale_references
      return false unless @record.respond_to?(:run_with) && @record.run_with.present?

      @record.run_with.each do |_key, value|
        if value.is_a?(String) && value.start_with?("gid://")
          begin
            GlobalID::Locator.locate(value)
          rescue ActiveRecord::RecordNotFound
            return true
          end
        end
      end

      false
    end

    def changed?(original, current)
      original.present? && current.present? && original.strip != current.strip
    end
  end
end
