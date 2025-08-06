# frozen_string_literal: true

module Raif
  module Generators
    class AgentGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)
      desc "Creates a new Raif::Agent subclass in app/models/raif/agents"

      class_option :skip_eval_set,
        type: :boolean,
        default: false,
        desc: "Skip generating the corresponding eval set"

      def create_application_agent
        template "application_agent.rb.tt", "app/models/raif/application_agent.rb" unless File.exist?("app/models/raif/application_agent.rb")
      end

      def create_agent
        template "agent.rb.tt", "app/models/raif/agents/#{file_name}.rb"
      end

      def create_directory
        empty_directory "app/models/raif/agents" unless File.directory?("app/models/raif/agents")
      end

      def create_eval_set
        return if options[:skip_eval_set]

        eval_set_path = if class_path.any?
          File.join("raif_evals", "eval_sets", class_path, "#{file_name}_agent_eval_set.rb")
        else
          File.join("raif_evals", "eval_sets", "#{file_name}_agent_eval_set.rb")
        end

        template "agent_eval_set.rb.tt", eval_set_path
      end

      def show_instructions
        say "\nAgent created!"
        say ""
      end

    private

      def class_name
        name.classify
      end

      def file_name
        name.underscore
      end
    end
  end
end
