# frozen_string_literal: true

require "optparse"
require_relative "base"

module Raif
  module CLI
    class Evals < Base
      def run
        # Set test environment by default for evals
        ENV["RAILS_ENV"] ||= "test"

        eval_sets = []

        OptionParser.new do |opts|
          opts.banner = "Usage: raif evals [options] [EVAL_SETS]"

          opts.on("-e", "--environment ENV", "Rails environment (default: test)") do |env|
            ENV["RAILS_ENV"] = env
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end.parse!(args)

        # Remaining arguments are eval set names
        eval_sets = args if args.any?

        # Find and load Rails application
        load_rails_application

        # Parse eval sets if specified
        eval_set_classes = if eval_sets.any?
          eval_sets.map do |class_name|
            class_name.constantize
          rescue NameError => e
            puts "Warning: Could not find eval set class #{class_name}: #{e.message}"
            nil
          end.compact
        end

        run = Raif::Evals::Run.new(eval_sets: eval_set_classes)
        run.execute
      end
    end
  end
end
