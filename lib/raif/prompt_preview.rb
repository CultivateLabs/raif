# frozen_string_literal: true

module Raif
  # Base class for prompt previews, similar to ActionMailer::Preview.
  #
  # Define preview methods that return configured task, conversation, or agent instances.
  # The preview system will render the prompt and system prompt for each method.
  #
  # Example:
  #   class Raif::Tasks::SummarizeDocumentPreview < Raif::PromptPreview
  #     def default
  #       Raif::Tasks::SummarizeDocument.new(document_text: "Sample text...", max_sentences: 3)
  #     end
  #
  #     def with_focus_areas
  #       Raif::Tasks::SummarizeDocument.new(
  #         document_text: "Sample text...",
  #         max_sentences: 5,
  #         focus_areas: ["key findings", "methodology"]
  #       )
  #     end
  #   end
  class PromptPreview
    class << self
      # Returns all preview classes found in the configured preview paths.
      def all
        load_previews
        descendants.sort_by(&:name)
      end

      # Returns a URL-friendly underscored identifier for this preview class.
      # e.g. "TestTemplateTaskPreview" -> "test_template_task_preview"
      def preview_id
        name.underscore.tr("/", "-")
      end

      # Returns the human-readable name for this preview class.
      def preview_name
        name
      end

      # Finds a preview class by its underscored preview_id.
      def find_by_preview_id(id)
        all.find { |k| k.preview_id == id }
      end

      # Returns all preview method names for this class.
      def preview_methods
        public_instance_methods(false).sort
      end

      # Returns the rendered prompt and system prompt for a given preview method.
      def render_preview(method_name)
        instance = new.public_send(method_name)
        {
          prompt: build_prompt_for(instance),
          system_prompt: build_system_prompt_for(instance),
          instance: instance
        }
      end

    private

      def load_previews
        Raif.config.prompt_preview_paths.each do |path|
          Dir[File.join(path, "**", "*_preview.rb")].sort.each { |f| require f }
        end
      end

      def build_prompt_for(instance)
        instance.build_prompt
      rescue NotImplementedError
        nil
      end

      def build_system_prompt_for(instance)
        instance.build_system_prompt
      rescue NotImplementedError
        nil
      end
    end
  end
end
