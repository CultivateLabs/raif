# frozen_string_literal: true

require "fileutils"
require "json"

module Raif
  module Evals
    class Run
      attr_reader :eval_sets, :results, :output

      def initialize(eval_sets: nil, output: $stdout)
        @eval_sets = eval_sets || discover_eval_sets
        @results = {}
        @output = output
      end

      def execute
        # Load setup file if it exists
        setup_file = Rails.root.join("raif_evals", "setup.rb")
        if File.exist?(setup_file)
          require setup_file
        else
          output.puts Raif::Utils::Colors.red("\n\nNo setup file found. To set up Raif evals, run:\n")
          output.puts Raif::Utils::Colors.red("bundle exec raif evals:setup\n")
          exit 1
        end

        output.puts "\nStarting Raif Eval Run"
        output.puts "Raif.config.default_llm_model_key: #{Raif.config.default_llm_model_key}"
        output.puts "=" * 50

        @eval_sets.each do |eval_set_class|
          output.puts "\nRunning #{eval_set_class.name}"
          output.puts "-" * 50

          eval_results = eval_set_class.run(output: output)
          @results[eval_set_class.name] = eval_results.map(&:to_h)

          passed_count = eval_results.count(&:passed?)
          total_count = eval_results.count

          output.puts "-" * 50
          output.puts "#{eval_set_class.name}: #{passed_count}/#{total_count} evals passed"
        end

        export_results
        print_summary
      end

    private

      def discover_eval_sets
        eval_sets_dir = Rails.root.join("raif_evals", "eval_sets")
        return [] unless eval_sets_dir.exist?

        Dir.glob(eval_sets_dir.join("**", "*_eval_set.rb")).map do |file|
          relative_path = Pathname.new(file).relative_path_from(Rails.root)
          require Rails.root.join(relative_path)

          class_name = File.basename(file, ".rb").camelize
          namespace_parts = relative_path.dirname.to_s.split("/")[2..-1]

          full_class_name = if namespace_parts&.any?
            (namespace_parts.map(&:camelize) + [class_name]).join("::")
          else
            class_name
          end

          full_class_name.constantize
        end.select { |klass| klass < Raif::Evals::EvalSet }
      end

      def export_results
        results_dir = Rails.root.join("raif_evals", "results")
        FileUtils.mkdir_p(results_dir)

        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        filename = results_dir.join("eval_run_#{timestamp}.json")

        File.write(filename, JSON.pretty_generate({
          run_at: Time.current.iso8601,
          results: @results,
          summary: summary_data
        }))

        output.puts "\nResults exported to: #{filename}"
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

        {
          total_eval_sets: total_eval_sets,
          total_evals: total_evals,
          passed_evals: passed_evals,
          total_expectations: total_expectations,
          passed_expectations: passed_expectations
        }
      end

      def print_summary
        data = summary_data

        output.puts ""
        output.puts "\n" + "=" * 50
        output.puts "SUMMARY"
        output.puts "=" * 50
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
      end
    end
  end
end
