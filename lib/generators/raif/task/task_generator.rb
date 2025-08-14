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

        # Remove 'raif' from class_path if it's the first element (Rails adds it automatically)
        eval_class_path = class_path.dup
        eval_class_path.shift if eval_class_path.first == "raif"

        eval_set_path = if eval_class_path.any?
          File.join("raif_evals", "eval_sets", "tasks", eval_class_path, "#{file_name}_eval_set.rb")
        else
          File.join("raif_evals", "eval_sets", "tasks", "#{file_name}_eval_set.rb")
        end

        template "task_eval_set.rb.tt", eval_set_path
      end

      def show_instructions
        say "\nTask created!"
        say ""
      end

    end
  end
end
