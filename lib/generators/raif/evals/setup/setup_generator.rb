# frozen_string_literal: true

require "rails/generators"

module Raif
  module Generators
    module Evals
      class SetupGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        RESULTS_GITIGNORE_PATH = "raif_evals/results/.gitignore"

        RUN_LOG_IGNORE = <<~EOS
          # Eval run logs are transient: the run each belongs to either finishes and replaces it
          # with a results file, or gets resumed. Keep this even if you delete the `*` above to
          # put result files in version control.
          *.partial.jsonl
        EOS

        def create_directories
          empty_directory "raif_evals"
          empty_directory "raif_evals/eval_sets"
          empty_directory "raif_evals/files"
          empty_directory "raif_evals/datasets"
          empty_directory "raif_evals/results"
        end

        def create_setup_file
          create_file "raif_evals/setup.rb", <<~EOS
            #
            # This file is loaded at the start of a run of your evals.
            #
            # Add any setup code that should run before your evals.
            #
          EOS
        end

        # Appends to an existing file rather than raising a conflict prompt, so an install made
        # before the run log pattern existed picks it up on a re-run.
        def create_gitignore
          existing_gitignore = File.join(destination_root, RESULTS_GITIGNORE_PATH)

          unless File.exist?(existing_gitignore)
            return create_file RESULTS_GITIGNORE_PATH, "*\n!.gitignore\n\n#{RUN_LOG_IGNORE}"
          end

          return if File.read(existing_gitignore).match?(/^\s*\*\.partial\.jsonl\s*$/)

          append_to_file RESULTS_GITIGNORE_PATH, "\n#{RUN_LOG_IGNORE}"
        end

        def show_instructions
          say "\nRaif evals setup complete!", :green
          say "You can create evals with: rails g raif:eval_set ExampleName"
          say ""
          say "Run evals with:"
          say "  bundle exec raif evals                                           # Run all evals"
          say "  bundle exec raif evals ./raif_evals/eval_sets/my_eval_set.rb     # Run specific eval set"
          say ""
        end
      end
    end
  end
end
