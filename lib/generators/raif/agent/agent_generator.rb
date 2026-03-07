# frozen_string_literal: true

require_relative "../base_generator"

module Raif
  module Generators
    class AgentGenerator < BaseGenerator
      source_root File.expand_path("templates", __dir__)
      desc "Creates a new Raif::Agent subclass in app/models/raif/agents"

      class_option :skip_eval_set,
        type: :boolean,
        default: false,
        desc: "Skip generating the corresponding eval set"

      class_option :skip_prompt_template,
        type: :boolean,
        default: false,
        desc: "Skip generating the system prompt template file"

      def create_application_agent
        template "application_agent.rb.tt", "app/models/raif/application_agent.rb" unless File.exist?("app/models/raif/application_agent.rb")
      end

      def create_agent
        template "agent.rb.tt", File.join("app/models/raif/agents", class_path, "#{file_name}.rb")
      end

      def create_system_prompt_template
        return if options[:skip_prompt_template]

        template "system_prompt.erb.tt", system_prompt_template_file_path
      end

      def create_directory
        empty_directory "app/models/raif/agents" unless File.directory?("app/models/raif/agents")
      end

      def create_eval_set
        return if options[:skip_eval_set]

        template "agent_eval_set.rb.tt", eval_set_file_path
      end

      def show_instructions
        say "\nAgent created!"
        unless options[:skip_prompt_template]
          say "  System prompt template: #{system_prompt_template_file_path}"
        end
        say ""
      end

    private

      def eval_set_file_path
        File.join("raif_evals", "eval_sets", "agents", class_path, "#{file_name}_eval_set.rb")
      end

      def system_prompt_template_file_path
        File.join("app/views/raif/agents", class_path, "#{file_name}.system_prompt.erb")
      end

    end
  end
end
