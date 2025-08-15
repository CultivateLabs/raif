# frozen_string_literal: true

require "optparse"
require_relative "base"

module Raif
  module CLI
    class Evals < Base
      def run
        # Set test environment by default for evals
        ENV["RAILS_ENV"] ||= "test"
        ENV["RAIF_RUNNING_EVALS"] = "true"

        OptionParser.new do |opts|
          opts.banner = "Usage: raif evals [options] [FILE_PATHS]"

          opts.on("-e", "--environment ENV", "Rails environment (default: test)") do |env|
            ENV["RAILS_ENV"] = env
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end.parse!(args)

        # Parse file paths with optional line numbers
        file_paths = args.map do |arg|
          if arg.include?(":")
            file_path, line_number = arg.split(":", 2)
            { file_path: file_path, line_number: line_number.to_i }
          else
            { file_path: arg, line_number: nil }
          end
        end if args.any?

        # Find and load Rails application
        load_rails_application

        require "raif/evals"

        run = Raif::Evals::Run.new(file_paths: file_paths)
        run.execute
      end
    end
  end
end
