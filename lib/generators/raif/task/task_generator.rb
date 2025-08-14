# frozen_string_literal: true

require_relative "../base_generator"

module Raif
  module Generators
    class TaskGenerator < BaseGenerator
      source_root File.expand_path("templates", __dir__)

      class_option :response_format,
        type: :string,
        default: "text",
        desc: "Response format for the task (text, html, or json)"

      class_option :skip_eval_set,
        type: :boolean,
        default: false,
        desc: "Skip generating the corresponding eval set"

      def create_application_task
        template "application_task.rb.tt", "app/models/raif/application_task.rb" unless File.exist?("app/models/raif/application_task.rb")
      end

      def create_task_file
        template "task.rb.tt", File.join("app/models/raif/tasks", class_path, "#{file_name}.rb")
      end

      def create_eval_set
        return if options[:skip_eval_set]

        template "task_eval_set.rb.tt", eval_set_file_path
      end

      def show_instructions
        say "\nTask created!"
        say ""
      end

    private

      def eval_set_file_path
        File.join("raif_evals", "eval_sets", "tasks", class_path, "#{file_name}_eval_set.rb")
      end

    end
  end
end
