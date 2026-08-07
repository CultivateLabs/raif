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

        repeats = ENV.fetch("RAIF_EVAL_REPEATS", 1).to_i
        cases = ENV["RAIF_EVAL_CASES"].to_s.split(",").map(&:strip).reject(&:empty?)
        sample = ENV["RAIF_EVAL_SAMPLE"]&.to_i
        seed = ENV["RAIF_EVAL_SEED"]&.to_i
        # nil leaves Raif.config.evals_verbose_output alone. An app that turned verbose
        # output on in its initializer needs a way back to the compact dataset output
        # without editing the initializer, so --no-verbose has to be able to win.
        verbose = case ENV["RAIF_EVAL_VERBOSE"]
        when nil, "" then nil
        when "0", "false" then false
        else true
        end

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: raif evals [options] [FILE_PATHS]"

          opts.on("-e", "--environment ENV", "Rails environment (default: test)") do |env|
            ENV["RAILS_ENV"] = env
          end

          opts.on("-r", "--repeat N", Integer, "Run each eval N times and report a pass rate (default: 1)") do |n|
            repeats = n
          end

          opts.on("--cases a,b,c", Array, "Run only these dataset cases") do |ids|
            cases = ids.map(&:strip).reject(&:empty?)
          end

          opts.on("--sample N", Integer, "Run a random N cases from each dataset") do |n|
            sample = n
          end

          opts.on("--seed N", Integer, "Seed for --sample, so the same cases can be drawn again") do |n|
            seed = n
          end

          opts.on("--[no-]verbose", "Print every expectation for every dataset case (default: Raif.config.evals_verbose_output)") do |value|
            verbose = value
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end

        parse_options!(parser)

        # A sample of zero or fewer cases is a typo, not a selection: Array#take would raise on a
        # negative count, and zero would run nothing and report an empty suite as a pass.
        if sample && sample < 1
          puts "Error: --sample must be 1 or greater (got #{sample})"
          exit 1
        end

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

        Raif.config.evals_verbose_output = verbose unless verbose.nil?

        run = Raif::Evals::Run.new(
          file_paths: file_paths,
          repeats: repeats,
          cases: (cases if cases.any?),
          sample: sample,
          seed: seed
        )
        run.execute
      end
    end
  end
end
