# frozen_string_literal: true

require "json"
require_relative "terminal"

# Formats bin/smoke's terminal and JSON output: progress-line summaries, the results matrix, the
# Details section, the per-run counts footer, and --format json. Split out of script/smoke.rb (which
# stays a thin CLI entry point -- ARGV parsing, credential setup, the run loop, and process exit) so
# this formatting logic is unit-testable the same way every other bin/smoke concern already is (see
# script/smoke/{checks,policy,selection}.rb and their specs).
module Smoke
  module Report
    STATUS_LABELS = {
      pass: "PASS",
      fail: "FAIL",
      skip: "SKIP",
      timeout: "TIMEOUT",
      note: "NOTE",
      consistent: "CONSISTENT"
    }.freeze

    CAPABILITY_COLUMN_ORDER = %w[
      completion temperature structured_outputs native_tool_use streaming
      streaming_tool_calls batch_inference images pdfs provider_managed_tools embedding
    ].freeze

    # Worst-first: a model's summary-footer bucket is its single worst capability status.
    # :consistent sits between :note and :pass -- it confirms a claimed-false manifest claim is
    # accurate (a benign, expected result, better than :note's "the manifest looks wrong"), but
    # it's still surfaced ahead of a plain :pass rather than folded into it.
    STATUS_PRIORITY = %i[fail timeout skip note consistent pass].freeze

    def self.status_label(status)
      STATUS_LABELS.fetch(status, status.to_s.upcase)
    end

    def self.progress_summary(capabilities)
      CAPABILITY_COLUMN_ORDER
        .select { |cap| capabilities.key?(cap) }
        .map { |cap| "#{cap}=#{Smoke::Terminal.status_paint(status_label(capabilities[cap][:status]), capabilities[cap][:status], stream: $stderr)}" }
        .join(" ")
    end

    def self.print_text_matrix(model_results)
      return if model_results.empty?

      columns = CAPABILITY_COLUMN_ORDER.select { |cap| model_results.any? { |result| result[:capabilities].key?(cap) } }
      key_width = (["MODEL".length] + model_results.map { |result| result[:key].length }).max
      column_widths = columns.to_h { |cap| [cap, [cap.length, "CONSISTENT".length].max] }

      # Separates the matrix from whatever came before it -- normally the last "progress: ..."
      # line on stderr, which interleaves with stdout in a real terminal with no line of its own
      # between them otherwise.
      puts

      header = "MODEL".ljust(key_width) + "  " + columns.map { |cap| cap.upcase.ljust(column_widths[cap]) }.join("  ")
      puts Smoke::Terminal.paint(header, :bold, stream: $stdout)

      model_results.each do |result|
        row = columns.map do |cap|
          cell = result[:capabilities][cap]

          if cell
            label = status_label(cell[:status]).ljust(column_widths[cap])
            Smoke::Terminal.status_paint(label, cell[:status], stream: $stdout)
          else
            Smoke::Terminal.paint("-".ljust(column_widths[cap]), :dim, stream: $stdout)
          end
        end.join("  ")

        puts result[:key].ljust(key_width) + "  " + row
      end

      details = model_results.flat_map do |result|
        result[:capabilities].filter_map do |cap, cell|
          next if cell[:status] == :pass

          label = Smoke::Terminal.status_paint(status_label(cell[:status]), cell[:status], stream: $stdout)
          "  #{result[:key]} #{cap}: #{label} #{cell[:detail]}"
        end
      end

      return if details.empty?

      puts
      puts "Details:"
      details.each { |line| puts line }
    end

    # A model's worst capability status, fail > timeout > skip > note > consistent > pass -- an
    # empty capabilities hash (an unexecuted required check; see Smoke::Policy) counts as fail,
    # since it's never a benign outcome. Used only to bucket the summary footer's per-model counts.
    def self.worst_model_status(capabilities)
      return :fail if capabilities.empty?

      statuses = capabilities.values.map { |cell| cell[:status] }
      STATUS_PRIORITY.find { |candidate| statuses.include?(candidate) } || :fail
    end

    def self.print_summary_footer(model_results, elapsed_seconds, exit_code)
      return if model_results.empty?

      counts = Hash.new(0)
      model_results.each { |result| counts[worst_model_status(result[:capabilities])] += 1 }

      line = "#{model_results.size} models: #{counts[:pass]} pass, #{counts[:fail]} fail, #{counts[:skip]} skip, " \
        "#{counts[:timeout]} timeout, #{counts[:note]} note, #{counts[:consistent]} consistent " \
        "(#{Smoke::Terminal.format_duration(elapsed_seconds)})"

      puts
      puts Smoke::Terminal.paint(line, exit_code.zero? ? :green : :red, stream: $stdout)
    end

    def self.print_json_results(model_results)
      payload = model_results.map do |result|
        {
          "key" => result[:key],
          "explicit" => result[:explicit],
          "capabilities" => result[:capabilities].transform_values { |cell| { "status" => cell[:status].to_s, "detail" => cell[:detail] } }
        }
      end

      puts JSON.pretty_generate(payload)
    end
  end
end
