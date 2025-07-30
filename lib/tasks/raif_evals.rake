# frozen_string_literal: true

namespace :raif do
  namespace :evals do
    desc "Run Raif evaluation sets"
    task run: :environment do
      # Load setup file if it exists
      setup_file = Rails.root.join("raif_evals", "setup.rb")
      require setup_file if setup_file.exist?

      # Parse EVAL_SETS environment variable
      eval_sets = if ENV["EVAL_SETS"].present?
        ENV["EVAL_SETS"].split(",").map(&:strip).map do |class_name|
          class_name.constantize
        rescue NameError => e
          puts "Warning: Could not find eval set class #{class_name}: #{e.message}"
          nil
        end.compact
      end

      # Run the eval sets
      run = Raif::Evals::Run.new(eval_sets: eval_sets)
      run.execute
    end

    desc "Setup Raif evals directory structure"
    task setup: :environment do
      # Create directories
      raif_evals_dir = Rails.root.join("raif_evals")
      eval_sets_dir = raif_evals_dir.join("eval_sets")
      files_dir = raif_evals_dir.join("files")
      results_dir = raif_evals_dir.join("results")

      [raif_evals_dir, eval_sets_dir, files_dir, results_dir].each do |dir|
        FileUtils.mkdir_p(dir)
        puts "Created directory: #{dir}"
      end

      # Create setup.rb file if it doesn't exist
      setup_file = raif_evals_dir.join("setup.rb")
      if setup_file.exist?
        puts "File already exists: #{setup_file}"
      else
        File.write(setup_file, <<~EOS)
          # raif_evals/setup.rb

          # Load the Rails environment
          ENV["RAILS_ENV"] ||= "test"
          require_relative "../config/environment"

          # Any other setup code you need
        EOS

        puts "Created file: #{setup_file}"
      end

      # Create .gitignore for results directory
      gitignore_file = results_dir.join(".gitignore")
      unless gitignore_file.exist?
        File.write(gitignore_file, "*\n!.gitignore\n")
        puts "Created file: #{gitignore_file}"
      end

      puts "\nRaif evals setup complete!"
      puts "You can create evals with: rails g raif:eval_set ExampleName"
      puts "Run evals with: rails raif:evals:run"
    end
  end
end
