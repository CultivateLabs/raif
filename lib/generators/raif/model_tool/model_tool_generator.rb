# frozen_string_literal: true

require_relative "../base_generator"

module Raif
  module Generators
    class ModelToolGenerator < BaseGenerator
      source_root File.expand_path("templates", __dir__)

      desc "Creates a new model tool for the LLM to invoke in app/models/raif/model_tools"

      def create_model_tool_file
        template "model_tool.rb.tt", File.join("app/models/raif/model_tools", class_path, "#{file_name}.rb")
        template "model_tool_invocation_partial.html.erb.tt", File.join("app/views/raif/model_tool_invocations", class_path, "_#{file_name}.html.erb")
      end

      def success_message
        say_status :success, "Model tool created successfully", :green
        say "\nYou can now implement your model tool in:"
        say "  app/models/raif/model_tools/#{file_name}.rb"
      end

    end
  end
end
