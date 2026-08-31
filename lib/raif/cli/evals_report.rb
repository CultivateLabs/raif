# frozen_string_literal: true

require "optparse"
require "json"
require_relative "base"

module Raif
  module CLI
    class EvalsReport < Base
      # Rails is deliberately not loaded, for the reason evals:compare does not: this reads one JSON
      # file and renders a template, so booting an app would make it the slowest part of the eval
      # tooling that needs no database or API key.
      def run
        require_relative "../evals/run_report"
        require_relative "../utils/colors"

        format = "html"
        output_path = nil

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: raif evals:report RESULTS.json [options]"

          opts.on("--format FORMAT", Raif::Evals::RunReport::FORMATS,
            "Output format: #{Raif::Evals::RunReport::FORMATS.join(", ")} (default: html)") do |value|
            format = value
          end

          opts.on("--output PATH", "Write to PATH instead of a .html file beside the results file") do |value|
            output_path = value
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end
        end

        parse_options!(parser)

        results_path = args.first
        if results_path.nil?
          puts parser
          exit 1
        end

        payload = load_payload(results_path)
        report = Raif::Evals::RunReport.new(payload, label: File.basename(results_path))

        output_path ||= default_output_path(results_path)
        File.write(output_path, report.render(format))

        puts "Run report written to: #{output_path}"
      end

    private

      def load_payload(path)
        unless File.exist?(path)
          puts Raif::Utils::Colors.red("Error: File not found: #{path}")
          exit 1
        end

        # Ahead of the parse, which a log of one JSON object per line fails on for a reason that
        # says nothing about what to do next. A run that stopped early leaves only this log.
        if File.extname(path) == ".jsonl"
          puts Raif::Utils::Colors.red(<<~MSG)
            Error: #{path} is a partial run log, not a results file.
            Finish the run with `raif evals --resume #{path}`, which writes the results file this reads.
          MSG
          exit 1
        end

        payload = begin
          JSON.parse(File.read(path))
        rescue JSON::ParserError => e
          puts Raif::Utils::Colors.red("Error: #{path} is not valid JSON: #{e.message}")
          exit 1
        end

        # Every key the report reads falls back to nil, so without a shape check an unrecognized
        # JSON object renders a page of empty tables rather than saying what went wrong.
        unless payload.is_a?(Hash) && payload["results"].is_a?(Hash)
          puts Raif::Utils::Colors.red(<<~MSG)
            Error: #{path} is not a Raif eval results file (no top-level "results" object).
            Pass one of the JSON files written to raif_evals/results by `raif evals`.
          MSG
          exit 1
        end

        payload
      end

      # Beside the results file, named after it, so a directory of runs sorts its reports next to
      # the data they came from.
      def default_output_path(results_path)
        File.join(
          File.dirname(results_path),
          "#{File.basename(results_path, ".json")}.html"
        )
      end
    end
  end
end
