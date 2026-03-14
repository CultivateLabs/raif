# frozen_string_literal: true

module Raif
  module Errors
    class PromptTemplateError < StandardError
      attr_reader :template_path, :original_error

      def initialize(template_path:, original_error:)
        @template_path = template_path
        @original_error = original_error
        super("Error rendering prompt template '#{template_path}': #{original_error.class}: #{original_error.message}")
      end
    end
  end
end
