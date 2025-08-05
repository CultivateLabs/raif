# frozen_string_literal: true

require "rails/generators"

module Raif
  module Generators
    module Evals
      class SetupGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        def create_directories
          empty_directory "raif_evals"
          empty_directory "raif_evals/eval_sets"
          empty_directory "raif_evals/files"
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

        def create_gitignore
          create_file "raif_evals/results/.gitignore", <<~EOS
            *
            !.gitignore
          EOS
        end

        def show_instructions
          say "\nRaif evals setup complete!", :green
          say "You can create evals with: rails g raif:eval_set ExampleName"
          say ""
          say "Run evals with:"
          say "  bundle exec raif evals                     # Run all evals in test env"
          say "  bundle exec raif evals CustomerSupport     # Run specific eval set"
          say "  bundle exec raif evals -e development      # Force different environment"
        end
      end
    end
  end
end