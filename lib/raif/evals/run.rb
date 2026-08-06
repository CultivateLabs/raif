# frozen_string_literal: true

require "fileutils"
require "json"

module Raif
  module Evals
    class Run
      attr_reader :eval_sets, :results, :output, :repeats, :cases, :sample, :seed

      def initialize(file_paths: nil, output: $stdout, repeats: 1, cases: nil, sample: nil, seed: nil)
        @output = output
        @results = {}
        @repeats = [repeats.to_i, 1].max
        @cases = cases.presence
        @sample = sample&.to_i
        @seed = seed&.to_i

        # Before the eval sets, not after: loading an eval set evaluates its class body,
        # so anything setup.rb defines for the sets to use (shared helper modules,
        # scoring rubrics) has to exist by then or the `include` raises NameError.
        load_setup_file

        @eval_sets = if file_paths&.any?
          load_eval_sets_from_files(file_paths)
        else
          discover_eval_sets
        end
      end

      def execute
        output.puts "\nStarting Raif Eval Run"
        output.puts ""
        output.puts "Raif.config.default_llm_model_key: #{Raif.config.default_llm_model_key}"
        output.puts "Raif.config.evals_default_llm_judge_model_key: #{Raif.config.evals_default_llm_judge_model_key}"
        output.puts "Repeats per eval: #{repeats}"
        output.puts "Cases: #{cases.join(", ")}" if cases
        output.puts "Sample per dataset: #{sample}#{" (seed #{seed})" if seed}" if sample
        output.puts ""
        output.puts "=" * 50

        @eval_sets.each do |eval_set_entry|
          eval_set_class, file_path, line_number = if eval_set_entry.is_a?(Hash)
            [eval_set_entry[:class], eval_set_entry[:file_path], eval_set_entry[:line_number]]
          else
            [eval_set_entry, nil, nil]
          end

          if line_number
            # Running specific eval by line number
            output.puts "\nRunning #{eval_set_class.name} at line #{line_number}"
            output.puts "-" * 50

            eval_results = run_eval_at_line(eval_set_class, file_path, line_number)
          else
            # Running all evals in the set
            output.puts "\nRunning #{eval_set_class.name}"
            output.puts "-" * 50

            eval_results = eval_set_class.run(output: output, repeats: repeats, cases: cases, sample: sample, seed: seed)
          end

          @results[eval_set_class.name] = eval_results.map(&:to_h)
          passed_count = eval_results.count(&:passed?)
          total_count = eval_results.count

          output.puts "-" * 50
          output.puts "#{eval_set_class.name}: #{passed_count}/#{total_count} evals passed"
        end

        # --cases filters every dataset in the run, so an id matching nothing anywhere is a
        # typo rather than a selection. Checked against the case ids that actually ran rather
        # than against the result count, since the non-dataset evals in the same set run
        # regardless and would otherwise make a typo look like a suite that passed.
        if cases && datasets_declared? && @results.values.flatten.none? { |e| e[:case_id] }
          output.puts Raif::Utils::Colors.red("\nNo eval cases matched --cases #{cases.join(",")}")
          exit 1
        end

        export_results
        print_summary
      end

    private

      def load_setup_file
        setup_file = Rails.root.join("raif_evals", "setup.rb")

        if File.exist?(setup_file)
          require setup_file
        else
          output.puts Raif::Utils::Colors.red("\n\nNo setup file found. To set up Raif evals, run:\n")
          output.puts Raif::Utils::Colors.red("bundle exec raif evals:setup\n")
          exit 1
        end
      end

      def load_eval_sets_from_files(file_paths)
        eval_sets = []

        file_paths.each do |f|
          file_path = f[:file_path]
          line_number = f[:line_number]

          # Convert relative path to absolute
          absolute_path = File.expand_path(file_path)

          unless File.exist?(absolute_path)
            output.puts Raif::Utils::Colors.red("Error: File not found: #{file_path}")
            exit 1
          end

          subclasses_before = Raif::Evals::EvalSet.subclasses

          require absolute_path

          # require is a no-op for a file already loaded (auto-discovery elsewhere in the
          # process, or the same path given twice), so the subclass diff can be empty for a
          # perfectly valid file. Fall back to matching the class by where its evals were
          # defined.
          loaded_eval_sets = Raif::Evals::EvalSet.subclasses - subclasses_before
          eval_set_class = loaded_eval_sets.first || eval_set_class_defined_in(absolute_path)

          eval_set_entry = { class: eval_set_class, file_path: absolute_path }
          eval_set_entry[:line_number] = line_number if line_number

          eval_sets << eval_set_entry
        end

        eval_sets
      end

      def datasets_declared?
        @eval_sets.any? do |eval_set_entry|
          eval_set_class = eval_set_entry.is_a?(Hash) ? eval_set_entry[:class] : eval_set_entry
          eval_set_class.datasets.any?
        end
      end

      def eval_set_class_defined_in(absolute_path)
        Raif::Evals::EvalSet.subclasses.find do |klass|
          klass.evals.any? { |eval_definition| eval_definition[:definition_file] == absolute_path }
        end
      end

      def run_eval_at_line(eval_set_class, file_path, line_number)
        target_eval = eval_set_class.evals.find{|e| e[:definition_line_number] == line_number }

        if target_eval.nil?
          output.puts Raif::Utils::Colors.red("Error: No eval block found at line #{line_number}")
          return []
        end

        instance = eval_set_class.new(output: output)
        instance.run_eval_definition(target_eval, repeats: repeats, cases: cases, sample: sample, seed: seed)
      end

      def discover_eval_sets
        eval_sets_dir = Rails.root.join("raif_evals", "eval_sets")
        return [] unless eval_sets_dir.exist?

        Dir.glob(eval_sets_dir.join("**", "*_eval_set.rb")).map do |file|
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          require Rails.root.join(relative_path)

          # Extract the path components after raif_evals/eval_sets
          path_from_eval_sets = Pathname.new(file).relative_path_from(eval_sets_dir)
          path_parts = path_from_eval_sets.dirname.to_s.split("/")

          # Remove "." if it's the only element (meaning file is in eval_sets root)
          path_parts = [] if path_parts == ["."]

          # Build the full class name
          class_name = File.basename(file, ".rb").camelize
          namespace_parts = ["Raif", "Evals"] + path_parts.map(&:camelize)
          full_class_name = (namespace_parts + [class_name]).join("::")

          full_class_name.constantize
        end.select { |klass| klass < Raif::Evals::EvalSet }
      end

      # The model key goes in both the filename and the payload: comparing models means
      # holding several result files side by side, and a run that only names its model in
      # stdout cannot be attributed back to one once the terminal is gone.
      def export_results
        results_dir = Rails.root.join("raif_evals", "results")
        FileUtils.mkdir_p(results_dir)

        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        filename = results_dir.join("eval_run_#{timestamp}_#{Raif.config.default_llm_model_key}.json")

        File.write(filename, JSON.pretty_generate({
          run_at: Time.current.iso8601,
          configuration: configuration_data,
          results: @results,
          summary: summary_data
        }))

        output.puts "\nResults exported to: #{filename}"
      end

      def configuration_data
        {
          default_llm_model_key: Raif.config.default_llm_model_key,
          evals_default_llm_judge_model_key: Raif.config.evals_default_llm_judge_model_key,
          repeats: repeats,
          capture_model_completions: Raif.config.evals_capture_model_completions.to_s,
          sample: sample,
          seed: seed
        }
      end

      # One row per distinct eval, collapsing its repeats into a pass rate - the comparable
      # number between models, since a single pass/fail cannot separate a real quality
      # difference from one unlucky sample.
      #
      # Grouped by eval_index rather than description: the DSL does not enforce unique
      # descriptions, and two same-named eval blocks would otherwise report 2N runs and one
      # blended rate instead of a rate each.
      #
      # A dataset eval also reports a rate per case, since a model can improve on average
      # while getting worse on one input. Non-dataset rows keep their existing keys.
      def eval_pass_rates
        grouped_evals.map do |eval_set_name, runs|
          passed = runs.count { |e| e[:passed] }

          next pass_rate_row(eval_set_name, runs, passed) unless runs.any? { |e| e[:case_id] }

          per_case = runs.group_by { |e| e[:case_id] }.map do |case_id, case_runs|
            case_passed = case_runs.count { |e| e[:passed] }
            { case_id: case_id, runs: case_runs.count, passed: case_passed, pass_rate: rate(case_passed, case_runs.count) }
          end

          {
            eval_set: eval_set_name,
            description: runs.first[:description],
            eval_index: runs.first[:eval_index],
            cases: per_case.count,
            repeats: repeats,
            runs: runs.count,
            passed: passed,
            pass_rate: rate(passed, runs.count),
            per_case: per_case
          }
        end
      end

      # One row per score name per eval. This is the number that ranks two models, and
      # stddev and ci95 sit next to it so a mean cannot be over-read: two models a tenth of
      # a point apart with a spread of half a point have not been distinguished.
      def score_summaries
        grouped_evals.flat_map do |eval_set_name, runs|
          entries = runs.flat_map do |e|
            (e[:scores] || []).map { |score| score.merge(case_id: e[:case_id]) }
          end

          entries.group_by { |score| score[:name] }.map do |name, scores|
            values = scores.map { |score| score[:value] }
            per_case = score_per_case(scores)

            {
              eval_set: eval_set_name,
              description: runs.first[:description],
              eval_index: runs.first[:eval_index],
              name: name,
              scale: scores.first[:scale],
              higher_is_better: scores.first[:higher_is_better],
              n: values.count,
              mean: round(Statistics.mean(values)),
              median: round(Statistics.median(values)),
              stddev: round(Statistics.stddev(values)),
              min: values.min,
              max: values.max,
              ci95: Statistics.bootstrap_ci95(per_case ? per_case.map { |c| c[:mean] } : values)&.map { |bound| round(bound) },
              per_case: per_case
            }.compact
          end
        end
      end

      def grouped_evals
        @results.flat_map do |eval_set_name, evals|
          evals.group_by { |e| e[:eval_index] || e[:description] }.map { |_key, runs| [eval_set_name, runs] }
        end
      end

      def pass_rate_row(eval_set_name, runs, passed)
        {
          eval_set: eval_set_name,
          description: runs.first[:description],
          runs: runs.count,
          passed: passed,
          pass_rate: rate(passed, runs.count)
        }
      end

      def score_per_case(scores)
        return unless scores.any? { |score| score[:case_id] }

        scores.group_by { |score| score[:case_id] }.map do |case_id, case_scores|
          case_values = case_scores.map { |score| score[:value] }
          { case_id: case_id, n: case_values.count, mean: round(Statistics.mean(case_values)) }
        end
      end

      def rate(passed, total)
        (passed.to_f / total).round(4)
      end

      def round(value)
        value&.round(4)
      end

      def summary_data
        total_eval_sets = @results.count
        total_evals = @results.values.sum(&:count)
        passed_evals = @results.values.sum { |evals| evals.count { |e| e[:passed] } }

        total_expectations = @results.values.sum do |evals|
          evals.sum { |e| e[:expectation_results].count }
        end

        passed_expectations = @results.values.sum do |evals|
          evals.sum { |e| e[:expectation_results].count { |r| r[:status] == :passed } }
        end

        all_evals = @results.values.flatten
        total_model_completions = all_evals.sum { |e| e.dig(:usage, :model_completions).to_i }
        total_prompt_tokens = all_evals.sum { |e| e.dig(:usage, :prompt_tokens).to_i }
        total_completion_tokens = all_evals.sum { |e| e.dig(:usage, :completion_tokens).to_i }
        total_tokens = all_evals.sum { |e| e.dig(:usage, :total_tokens).to_i }
        total_cost = all_evals.sum { |e| e.dig(:usage, :total_cost).to_f }.round(6)

        {
          total_eval_sets: total_eval_sets,
          total_evals: total_evals,
          passed_evals: passed_evals,
          total_expectations: total_expectations,
          passed_expectations: passed_expectations,
          total_model_completions: total_model_completions,
          total_prompt_tokens: total_prompt_tokens,
          total_completion_tokens: total_completion_tokens,
          total_tokens: total_tokens,
          total_cost: total_cost,
          eval_pass_rates: eval_pass_rates,
          score_summaries: score_summaries
        }
      end

      def print_summary
        data = summary_data

        output.puts ""
        output.puts "\n" + "=" * 50
        output.puts "SUMMARY"
        output.puts "=" * 50
        output.puts "Model: #{Raif.config.default_llm_model_key}"
        output.puts "Judge: #{Raif.config.evals_default_llm_judge_model_key}"
        output.puts "Eval Sets: #{data[:total_eval_sets]}"
        output.puts ""
        output.puts "Evals:"
        output.puts "  #{data[:total_evals]} total"
        output.puts Raif::Utils::Colors.green("  #{data[:passed_evals]} passed")
        output.puts Raif::Utils::Colors.red("  #{data[:total_evals] - data[:passed_evals]} failed")
        output.puts ""
        output.puts "Expectations:"
        output.puts "  #{data[:total_expectations]} total"
        output.puts Raif::Utils::Colors.green("  #{data[:passed_expectations]} passed")
        output.puts Raif::Utils::Colors.red("  #{data[:total_expectations] - data[:passed_expectations]} failed")
        output.puts ""
        output.puts "LLM Usage:"
        output.puts "  #{data[:total_model_completions]} LLM calls"
        output.puts "  #{data[:total_prompt_tokens]} prompt tokens"
        output.puts "  #{data[:total_completion_tokens]} completion tokens"
        output.puts "  #{data[:total_tokens]} total tokens"
        output.puts "  $#{format("%.6f", data[:total_cost])} total cost"
        output.puts ""

        # A dataset eval has a rate worth printing even at --repeat 1, because the rate is
        # then over inputs rather than over repeats of one input.
        if repeats > 1 || data[:eval_pass_rates].any? { |row| row[:per_case] }
          output.puts "Pass rates:"
          data[:eval_pass_rates].each do |row|
            output.puts "  #{colorized_rate(row)} #{row[:eval_set]}: #{row[:description]}"

            row[:per_case]&.each do |per_case|
              output.puts "    #{colorized_rate(per_case)} #{per_case[:case_id]}"
            end
          end
          output.puts ""
        end

        if data[:score_summaries].any?
          output.puts "Scores:"
          data[:score_summaries].each do |row|
            spread = ["n #{row[:n]}"]
            spread << "sd #{row[:stddev]}" if row[:stddev]
            spread << "ci95 [#{row[:ci95].join(", ")}]" if row[:ci95]

            output.puts "  #{row[:name]}: mean #{row[:mean]} (#{spread.join(", ")}) #{row[:eval_set]}: #{row[:description]}"

            row[:per_case]&.each do |per_case|
              output.puts "    #{per_case[:mean]} #{per_case[:case_id]} (n #{per_case[:n]})"
            end
          end
          output.puts ""
        end
      end

      def colorized_rate(row)
        rate = "#{row[:passed]}/#{row[:runs]} (#{(row[:pass_rate] * 100).round}%)"
        colorize = if row[:pass_rate] == 1.0
          :green
        elsif row[:pass_rate].zero?
          :red
        else
          :yellow
        end

        Raif::Utils::Colors.public_send(colorize, rate)
      end
    end
  end
end
