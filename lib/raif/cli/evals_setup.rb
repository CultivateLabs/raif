# frozen_string_literal: true

require "fileutils"
require "optparse"
require_relative "base"

module Raif
  module CLI
    class EvalsSetup < Base
      def run
        OptionParser.new do |opts|
          opts.banner = "Usage: raif evals:setup [options]"
          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end.parse!(args)

        # Find Rails root (but don't load Rails - we don't need it for setup)
        rails_root = find_rails_root
        Dir.chdir(rails_root)

        create_directories(rails_root)
        create_setup_file(rails_root)
        create_gitignore(rails_root)
        show_completion_message
      end

    private

      def create_directories(rails_root)
        # Create directories
        raif_evals_dir = File.join(rails_root, "raif_evals")
        eval_sets_dir = File.join(raif_evals_dir, "eval_sets")
        files_dir = File.join(raif_evals_dir, "files")
        results_dir = File.join(raif_evals_dir, "results")

        [raif_evals_dir, eval_sets_dir, files_dir, results_dir].each do |dir|
          FileUtils.mkdir_p(dir)
          puts "Created directory: #{dir}"
        end
      end

      def create_setup_file(rails_root)
        setup_file = File.join(rails_root, "raif_evals", "setup.rb")
        if File.exist?(setup_file)
          puts "File already exists: #{setup_file}"
        else
          File.write(setup_file, setup_file_content)
          puts "Created file: #{setup_file}"
        end
      end

      def create_gitignore(rails_root)
        gitignore_file = File.join(rails_root, "raif_evals", "results", ".gitignore")
        unless File.exist?(gitignore_file)
          File.write(gitignore_file, "*\n!.gitignore\n")
          puts "Created file: #{gitignore_file}"
        end
      end

      def setup_file_content
        <<~EOS
          #
          # This file is loaded at the start of a run of your evals.
          #
          # Add any setup code that should run before your evals.
          #
        EOS
      end

      def show_completion_message
        puts "\nRaif evals setup complete!"
        puts "You can create evals with: rails g raif:eval_set ExampleName"
        puts ""
        puts "Run evals with:"
        puts "  bundle exec raif evals                     # Run all evals in test env"
        puts "  bundle exec raif evals CustomerSupport     # Run specific eval set"
        puts "  bundle exec raif evals -e development      # Force different environment"
      end
    end
  end
end
