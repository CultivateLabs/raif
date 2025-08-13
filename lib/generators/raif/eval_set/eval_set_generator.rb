# frozen_string_literal: true

require "rails/generators"

module Raif
  module Generators
    class EvalSetGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :name, type: :string, banner: "EvalSetName or Module::EvalSetName"

      class_option :type,
        type: :string,
        desc: "Type of eval set (Task, Conversation, or Agent) for organization"

      def create_eval_set_file
        @class_path = name.split("::")
        @class_name_without_namespace = @class_path.pop

        # Build the full class name based on the type option
        namespace_parts = ["Raif", "Evals"]
        namespace_parts << options[:type].capitalize if options[:type]
        namespace_parts += @class_path if @class_path.any?
        @full_class_name = (namespace_parts + [@class_name_without_namespace + "EvalSet"]).join("::")

        # Build the file path based on the type option
        path_parts = ["raif_evals", "eval_sets"]
        path_parts << options[:type] if options[:type]
        path_parts += @class_path.map(&:underscore) if @class_path.any?

        file_path = File.join(*path_parts, "#{@class_name_without_namespace.underscore}_eval_set.rb")

        template "eval_set.rb.erb", file_path
      end

      def create_files_directory
        empty_directory File.join("raif_evals", "files")
      end

      def create_results_directory
        empty_directory File.join("raif_evals", "results")
        create_file File.join("raif_evals", "results", ".gitignore"), "*\n!.gitignore\n"
      end

      def show_instructions
        say "\nEval set created!"
        say "To run this eval set: bundle exec raif evals #{@full_class_name}"
        say "To run all eval sets: bundle exec raif evals"
        say ""
      end
    end
  end
end
