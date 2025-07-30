# frozen_string_literal: true

require_relative "cli/base"
require_relative "cli/evals"
require_relative "cli/evals_setup"

module Raif
  module CLI
    COMMANDS = {
      "evals" => "Run Raif evaluation sets",
      "evals:setup" => "Setup Raif evals directory structure",
      "version" => "Show Raif version",
      "help" => "Show this help message"
    }.freeze

    class Runner
      def initialize(args)
        @args = args
        @command = args.shift
      end

      def run
        case @command
        when "evals"
          Evals.new(@args).run
        when "evals:setup"
          EvalsSetup.new(@args).run
        when "version", "--version", "-v"
          show_version
        when "help", "--help", "-h", nil
          show_help
        else
          puts "Unknown command: #{@command}"
          puts ""
          show_help
          exit 1
        end
      end

    private

      def show_version
        require_relative "../raif/version"
        puts "Raif #{Raif::VERSION}"
      end

      def show_help
        puts "Usage: raif COMMAND [options]"
        puts ""
        puts "Commands:"
        COMMANDS.each do |command, description|
          puts format("  %-12s %s", command, description)
        end
        puts ""
        puts "For help on a specific command:"
        puts "  raif COMMAND --help"
        puts ""
        puts "Examples:"
        puts "  raif evals:setup                  # Setup eval directory structure"
        puts "  raif evals                        # Run all eval sets in test environment"
        puts "  raif evals CustomerSupportEvalSet # Run specific eval set"
        puts "  raif evals -e development         # Run evals in development environment"
        puts "  raif version                      # Show Raif version"
      end
    end
  end
end
