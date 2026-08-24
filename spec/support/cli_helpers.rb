# frozen_string_literal: true

require "open3"
require "tmpdir"

module Raif
  module CliHelpers
    EXE_PATH = Raif::Engine.root.join("exe", "raif").to_s

    # The environment a child needs to run outside the bundle. RUBYOPT alone is not enough:
    # RubyGems requires BUNDLER_SETUP on its own, so the child would load the bundle anyway.
    # Under a non-default BUNDLE_GEMFILE that bundle is not even the installed one, and the
    # child dies in Bundler before it reaches the CLI.
    UNBUNDLED_ENV = {
      "RUBYOPT" => nil,
      "RUBYLIB" => nil,
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_SETUP" => nil
    }.freeze

    CliResult = Struct.new(:stdout, :stderr, :status) do
      def exit_code
        status.exitstatus
      end

      def output
        "#{stdout}#{stderr}"
      end
    end

    # Runs the real executable in a child process with the bundler environment stripped, so
    # the command has to require everything it uses. An in-process spec cannot check that:
    # rails_helper has already loaded the whole engine, which hides a missing require in a
    # command that is contracted to run without Rails.
    def run_raif_cli(*args)
      stdout, stderr, status = Open3.capture3(UNBUNDLED_ENV, RbConfig.ruby, EXE_PATH, *args.map(&:to_s))

      CliResult.new(stdout, stderr, status)
    end

    # Same, but reports whether Rails ended up loaded in the child.
    def run_raif_cli_reporting_rails(*args)
      script = <<~'RUBY'
        require ARGV.shift
        at_exit { warn "RAILS_DEFINED=#{!defined?(Rails).nil?}" }
        Raif::CLI::Runner.new(ARGV).run
      RUBY

      cli_path = Raif::Engine.root.join("lib", "raif", "cli").to_s
      stdout, stderr, status = Open3.capture3(UNBUNDLED_ENV, RbConfig.ruby, "-e", script, "--", cli_path, *args.map(&:to_s))

      CliResult.new(stdout, stderr, status)
    end

    # A minimal results payload of the shape `raif evals` exports.
    #
    # case_ids defaults to a single case, enough for the specs that only care about the payload's
    # shape. The regression gate tests matched cases, so a spec about the gate has to pass enough
    # of them for a verdict to be reachable - see "exits 1" below.
    #
    # errored_case_ids are cases that raised: no score, and an expectation whose status is "error".
    # Written without an "errored" key, as a results file from before that key would be.
    def cli_results_payload(model:, passed:, score_value:, judge: "judge_model", cost: 0.1,
      expectation_description: "is under 1000 words", case_ids: ["press-release"], errored_case_ids: [], datasets: nil)
      results = case_ids.map do |case_id|
        errored = errored_case_ids.include?(case_id)
        status = errored ? "error" : (passed ? "passed" : "failed")
        clarity = { "name" => "clarity", "value" => score_value, "scale" => "1..5", "higher_is_better" => true, "min" => 4 }

        {
          "description" => "produces expected output",
          "eval_id" => "SummarizationEvalSet#produces-expected-output-9c1de4a70b2f",
          "eval_index" => 0,
          "case_id" => case_id,
          "passed" => passed && !errored,
          "expectation_results" => [{ "description" => expectation_description, "status" => status }],
          "scores" => errored ? [] : [clarity]
        }
      end

      configuration = {
        "default_llm_model_key" => model,
        "evals_default_llm_judge_model_key" => judge,
        "judge_model_key" => judge,
        "repeats" => 1
      }
      # Absent unless a spec asks for it, which is how a results file written before datasets were
      # fingerprinted reads.
      configuration["datasets"] = datasets unless datasets.nil?

      {
        "run_at" => "2026-08-04T18:02:16Z",
        "configuration" => configuration,
        "results" => { "SummarizationEvalSet" => results },
        "summary" => {
          "passed_evals" => results.count { |result| result["passed"] },
          "total_evals" => results.count,
          "passed_expectations" => results.count { |result| result["expectation_results"].all? { |e| e["status"] == "passed" } },
          "total_expectations" => results.count,
          "total_cost" => cost
        }
      }
    end

    def write_payload(dir, name, payload)
      path = File.join(dir, name)
      File.write(path, JSON.generate(payload))
      path
    end
  end
end
