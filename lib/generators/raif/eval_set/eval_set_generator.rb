# frozen_string_literal: true

require_relative "../base_generator"

module Raif
  module Generators
    class EvalSetGenerator < BaseGenerator
      source_root File.expand_path("templates", __dir__)

      def create_eval_set_file
        template "eval_set.rb.tt", eval_set_file_path
      end

      def show_instructions
        say "\nEval set created!"
        say "To run this eval set: bundle exec raif evals ./#{eval_set_file_path}"
        say "To run all eval sets: bundle exec raif evals"
        say ""
      end

    private

      def eval_set_file_path
        File.join("raif_evals", "eval_sets", class_path, "#{file_name}_eval_set.rb")
      end
    end
  end
end
