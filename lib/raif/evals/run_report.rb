# frozen_string_literal: true

require "erb"
require "json"

module Raif
  module Evals
    # Renders one eval run's results file as a self-contained HTML page.
    #
    # Raif::Evals::ComparisonReport answers "what moved between two runs". This answers "what
    # happened in this one", which is the question a run with no baseline leaves you holding: the
    # console output scrolls away, and the results JSON is the wrong shape to read by eye.
    #
    # Input is the parsed results file. Keys are normalized to strings on the way in, so the hash
    # Raif::Evals::Run holds in memory renders the same as the file it writes.
    class RunReport
      TEMPLATE_PATH = File.expand_path("run_report.html.erb", __dir__)

      FORMATS = ["html"].freeze

      # What Raif::Evals::EvalResult strips under `summary` capture and keeps under `full`. Present
      # in the file only in the second case, which is why the footer says which one it was.
      COMPLETION_TEXT_KEYS = ["system_prompt", "messages", "response", "response_array", "response_tool_calls"].freeze

      attr_reader :payload, :label

      def initialize(payload, label: nil)
        @payload = stringify(payload)
        @label = label
      end

      def render(format = "html")
        case format.to_s
        when "html" then html
        else raise ArgumentError, "Unsupported format: #{format}. Supported: #{FORMATS.join(", ")}"
        end
      end

      def html
        ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-").result(binding)
      end

      def summary
        payload["summary"] || {}
      end

      def configuration
        payload["configuration"] || {}
      end

      # Eval set name => its results, in the order the results file holds them, which Raif::Evals::Run
      # has already put back into definition order.
      def eval_sets
        payload["results"] || {}
      end

      def run_at
        payload["run_at"].to_s.sub("T", " ")[0, 16]
      end

      def model
        configuration["default_llm_model_key"]
      end

      # What actually graded, rather than what was configured: a run with no judge configured is
      # graded by the model under test, and the configured key is null for it.
      def judge
        configuration["judge_model_key"] || configuration["evals_default_llm_judge_model_key"]
      end

      def repeats
        configuration["repeats"] || 1
      end

      # "none" rather than "" for a run recorded before the setting existed: the report says what
      # the file holds, and an empty cell says nothing.
      def capture_mode
        mode = configuration["capture_model_completions"].to_s
        mode.empty? ? "none" : mode
      end

      # Every expectation that did not pass, flattened across the whole run and carrying enough
      # context to find it again. This is the section a reader wants first, and reaching it by
      # scrolling a full drill-down defeats the point of writing one.
      def failures
        eval_sets.flat_map do |eval_set_name, results|
          results.flat_map do |result|
            (result["expectation_results"] || [])
              .reject { |expectation| expectation["status"].to_s == "passed" }
              .map do |expectation|
                {
                  "eval_set" => eval_set_name,
                  "description" => result["description"],
                  "case_id" => result["case_id"],
                  "expectation" => expectation
                }
              end
          end
        end
      end

      def pass_rate_rows
        summary["eval_pass_rates"] || []
      end

      def score_rows
        summary["score_summaries"] || []
      end

      def dataset_rows
        configuration["datasets"] || []
      end

      def total_cost
        summary["total_cost"].to_f
      end

      def completion_text(completion)
        COMPLETION_TEXT_KEYS.filter_map do |key|
          value = completion[key]
          [key, value] if value.is_a?(String) ? !value.strip.empty? : !value.nil?
        end
      end

      def describe_code
        code = configuration["code"]
        return "unknown" if code.nil?

        "#{code["git_sha"].to_s[0, 12]}#{" (dirty)" if code["dirty"]}"
      end

      def status_class(status)
        case status.to_s
        when "passed" then "good"
        when "error" then "warn"
        else "bad"
        end
      end

      # nil rather than 0.0 when every run of an eval or a case errored: Raif::Evals::Run leaves
      # the rate unset there, and a zero would report an outage as a total quality failure.
      def format_rate(rate)
        return "-" if rate.nil?

        format("%.2f", rate.to_f)
      end

      def rate_class(rate)
        return "warn" if rate.nil?

        rate.to_f >= 1.0 ? "good" : "bad"
      end

      # What `passed` is out of: errored runs leave the denominator, so a row that ran 4 times,
      # passed 3 and errored once is 3/3.
      def measured(row)
        row["runs"].to_i - row["errored"].to_i
      end

      # Cases that measured something and did not pass every run. A case with no rate measured
      # nothing, so it is reported as errored rather than as the weakest case in the eval.
      def failing_cases(row)
        (row["per_case"] || []).reject { |c| c["pass_rate"].nil? || c["pass_rate"].to_f >= 1.0 }
      end

      def errored_cases(row)
        (row["per_case"] || []).select { |c| c["pass_rate"].nil? }
      end

      # An eval that raised produced no measurement, so it is neither a pass nor a fail. Raif
      # keeps the three apart everywhere else, and a red FAIL on a provider timeout reads as a
      # quality regression.
      def result_status(result)
        return ["ERROR", "warn"] if result["errored"]

        result["passed"] ? ["PASS", "good"] : ["FAIL", "bad"]
      end

      # An eval set whose only shortfall is errors is not a failing eval set: nothing it ran
      # measured worse, so it reads as a warning rather than as red.
      def eval_set_class(results)
        measured_results = results.reject { |result| result["errored"] }
        return "bad" unless measured_results.all? { |result| result["passed"] }

        measured_results.count == results.count ? "good" : "warn"
      end

      # The bounds the score was actually gated on, in the shape Raif::Evals::ScoreResult states
      # them: a max: gate is the supported form for a lower-is-better metric, and a score can
      # carry both bounds.
      def gate_description(score)
        bounds = []
        bounds << ">= #{score["min"]}" unless score["min"].nil?
        bounds << "<= #{score["max"]}" unless score["max"].nil?

        bounds.join(" and ")
      end

      def format_cost(cost)
        return "-" if cost.nil?

        "$#{format("%.2f", cost.to_f)}"
      end

      def format_number(value)
        value.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      end

      # Model output reaches this page as expectation metadata and judge reasoning, so every
      # interpolation in the template goes through here. A report is a file people forward.
      def h(value)
        ERB::Util.html_escape(value.to_s)
      end

      def pretty(value)
        JSON.pretty_generate(value)
      rescue JSON::GeneratorError, TypeError
        value.inspect
      end

    private

      def stringify(value)
        case value
        when Hash then value.to_h { |key, nested| [key.to_s, stringify(nested)] }
        when Array then value.map { |nested| stringify(nested) }
        else value
        end
      end
    end
  end
end
