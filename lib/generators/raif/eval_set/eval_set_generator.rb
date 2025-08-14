# frozen_string_literal: true

require_relative "../base_generator"

module Raif
  module Generators
    class EvalSetGenerator < BaseGenerator
      source_root File.expand_path("templates", __dir__)

      def create_eval_set_file
        template "eval_set.rb.tt", File.join("raif_evals", "eval_sets", class_path, "#{file_name}_eval_set.rb")
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
        say "To run this eval set: bundle exec raif evals Raif::EvalSets::#{class_name}EvalSet"
        say "To run all eval sets: bundle exec raif evals"
        say ""
      end
    end
  end
end
