# frozen_string_literal: true

require "rails/generators"

module Raif
  module Generators
    class EvalSetGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :name, type: :string, banner: "EvalSetName or Module::EvalSetName"

      def create_eval_set_file
        @class_path = name.split("::")
        @class_name_without_namespace = @class_path.pop
        @full_class_name = (@class_path + [@class_name_without_namespace + "EvalSet"]).join("::")

        file_path = if @class_path.any?
          File.join("raif_evals", "eval_sets", @class_path.map(&:underscore), "#{@class_name_without_namespace.underscore}_eval_set.rb")
        else
          File.join("raif_evals", "eval_sets", "#{@class_name_without_namespace.underscore}_eval_set.rb")
        end

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
        say "\nEval set created! You can now:"
        say "  1. Add eval blocks to your new eval set"
        say "  2. Run it with: rails raif:evals:run EVAL_SETS=#{name}EvalSet"
        say "  3. Or run all eval sets with: rails raif:evals:run"
      end
    end
  end
end
