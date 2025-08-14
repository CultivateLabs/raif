# frozen_string_literal: true

require_relative "../base_generator"

module Raif
  module Generators
    class ConversationGenerator < BaseGenerator
      source_root File.expand_path("templates", __dir__)

      desc "Creates a new conversation type in the app/models/raif/conversations directory"

      class_option :response_format,
        type: :string,
        default: "text",
        desc: "Response format for the task (text, html, or json)"

      class_option :skip_eval_set,
        type: :boolean,
        default: false,
        desc: "Skip generating the corresponding eval set"

      def create_application_conversation
        template "application_conversation.rb.tt",
          "app/models/raif/application_conversation.rb" unless File.exist?("app/models/raif/application_conversation.rb")
      end

      def create_conversation_file
        template "conversation.rb.tt", File.join("app/models/raif/conversations", class_path, "#{file_name}.rb")
      end

      def create_directory
        empty_directory "app/models/raif/conversations" unless File.directory?("app/models/raif/conversations")
      end

      def create_eval_set
        return if options[:skip_eval_set]

        # Remove 'raif' from class_path if it's the first element (Rails adds it automatically)
        eval_class_path = class_path.dup
        eval_class_path.shift if eval_class_path.first == "raif"

        eval_set_path = if eval_class_path.any?
          File.join("raif_evals", "eval_sets", "conversations", eval_class_path, "#{file_name}_eval_set.rb")
        else
          File.join("raif_evals", "eval_sets", "conversations", "#{file_name}_eval_set.rb")
        end

        template "conversation_eval_set.rb.tt", eval_set_path
      end

      def success_message
        say_status :success, "Conversation type created successfully", :green
        say "\nYou can now implement your conversation type in:"
        say "  app/models/raif/conversations/#{file_name}.rb\n\n"
        say "\nDon't forget to add it to the config.conversation_types in your Raif configuration"
        say "For example: config.conversation_types += ['Raif::Conversations::#{class_name}']\n\n"
      end
    end
  end
end
