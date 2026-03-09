# frozen_string_literal: true

module Raif
  module Concerns
    module HasPromptTemplates
      extend ActiveSupport::Concern

      class TemplateContext < ActionView::Base.with_empty_template_cache
        def initialize(lookup_context, instance)
          super(lookup_context, {}, nil)
          @_instance = instance
        end

        def method_missing(method_name, ...)
          if @_instance.respond_to?(method_name)
            @_instance.public_send(method_name, ...)
          else
            super
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          @_instance.respond_to?(method_name, include_private) || super
        end
      end

      class_methods do
        # Returns the template prefix path derived from the class name.
        # e.g. Raif::Tasks::SummarizeDocument -> "raif/tasks/summarize_document"
        # e.g. Raif::Tasks::Docs::Summarize  -> "raif/tasks/docs/summarize"
        def prompt_template_prefix
          name.underscore
        end

        def prompt_template_view_paths
          ActionController::Base.view_paths
        end
      end

      def build_prompt
        if prompt_template_exists?(:prompt)
          render_prompt_template(:prompt)
        else
          super
        end
      end

      def build_system_prompt
        if prompt_template_exists?(:system_prompt)
          render_prompt_template(:system_prompt)
        else
          super
        end
      end

    private

      def prompt_template_name
        self.class.prompt_template_prefix.split("/").last
      end

      def prompt_template_dir
        File.dirname(self.class.prompt_template_prefix)
      end

      def prompt_template_exists?(template_type)
        prompt_lookup_context_for(template_type).exists?(prompt_template_name, prompt_template_dir)
      end

      def prompt_lookup_context_for(template_type)
        lookup = ActionView::LookupContext.new(self.class.prompt_template_view_paths)
        lookup.formats = [template_type]
        lookup
      end

      def render_prompt_template(template_type)
        lookup = prompt_lookup_context_for(template_type)
        context = TemplateContext.new(lookup, self)
        context.render(template: "#{prompt_template_dir}/#{prompt_template_name}").strip
      rescue ActionView::Template::Error, ActionView::MissingTemplate => e
        raise Raif::Errors::PromptTemplateError.new(
          template_path: "#{self.class.prompt_template_prefix}.#{template_type}.erb",
          original_error: e
        )
      end
    end
  end
end
