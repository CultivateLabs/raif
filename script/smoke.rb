# frozen_string_literal: true

# See bin/smoke for usage instructions.
#
# Runs the smoke capability checks (script/smoke/checks.rb) against the live models described in
# model_manifest/*.yml, using script/smoke/selection.rb to resolve CLI selectors, script/smoke/credentials.rb
# to gate providers on configured credentials, script/smoke/policy.rb to decide the process exit code, and
# script/smoke/recorder.rb (with --record) to write verified results back into the manifest.

require "optparse"
require "json"
require "raif/model_manifest"
require_relative "smoke/selection"
require_relative "smoke/credentials"
require_relative "smoke/checks"
require_relative "smoke/policy"
require_relative "smoke/recorder"

STATUS_LABELS = {
  pass: "PASS",
  fail: "FAIL",
  skip: "SKIP",
  timeout: "TIMEOUT",
  note: "NOTE"
}.freeze

CAPABILITY_COLUMN_ORDER = %w[
  completion temperature structured_outputs native_tool_use streaming
  streaming_tool_calls batch_inference images pdfs provider_managed_tools embedding
].freeze

EMBEDDING_PROMPT = "hello smoke"

def status_label(status)
  STATUS_LABELS.fetch(status, status.to_s.upcase)
end

# Builds the single capability result representing "this model's provider has no credentials
# configured" -- never an empty capabilities hash, since Smoke::Policy.exit_code treats an empty
# hash as an unexecuted required check and fails the run for every model, explicit or not.
def credential_skip_capabilities(entry, provider_name)
  detail = "missing credentials for #{provider_name}. #{Smoke::Credentials.instructions_for(provider_name)}"
  capability = entry.is_a?(Raif::ModelManifest::EmbeddingEntry) ? "embedding" : "completion"
  { capability => { status: :skip, detail: detail } }
end

def run_embedding_check(entry)
  embedding_model = Raif.embedding_model(entry.key)
  vector = embedding_model.generate_embedding!(EMBEDDING_PROMPT)
  size = vector.respond_to?(:length) ? vector.length : nil
  pass = size == entry.default_output_vector_size
  { status: pass ? :pass : :fail, detail: "vector_size=#{size.inspect} expected=#{entry.default_output_vector_size}" }
rescue StandardError => e
  { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
end

def run_entry(entry, options, explicit_keys, missing_credentials:)
  key = entry.key.to_s
  explicit = explicit_keys.include?(key)

  if missing_credentials
    return { key: key, explicit: explicit, capabilities: credential_skip_capabilities(entry, entry.provider_name) }
  end

  if entry.is_a?(Raif::ModelManifest::EmbeddingEntry)
    return { key: key, explicit: explicit, capabilities: { "embedding" => run_embedding_check(entry) } }
  end

  capabilities = Smoke::Checks.run_for(
    entry, only: options[:only], skip: options[:skip], iterations: options[:iterations], batch_timeout: options[:batch_timeout]
  )

  if options[:record]
    ran_full_unskipped = options[:only].nil? && options[:skip].empty? &&
      capabilities.values.none? { |result| %i[skip timeout].include?(result[:status]) }
    Smoke::Recorder.record!(entry, capabilities, ran_full_unskipped: ran_full_unskipped, now: Time.now.utc)
  end

  { key: key, explicit: explicit, capabilities: capabilities }
end

def run_all(selection, options)
  entries = selection[:entries] + selection[:embedding_entries]

  threads = entries.group_by(&:provider_name).map do |provider_name, group|
    Thread.new do
      missing_credentials = Smoke::Credentials.missing_for?(provider_name)

      if missing_credentials
        instructions = Smoke::Credentials.instructions_for(provider_name)
        warn "NOTE #{provider_name}: missing credentials, skipping #{group.size} model(s). #{instructions}"
      end

      group.map { |entry| run_entry(entry, options, selection[:explicit_keys], missing_credentials: missing_credentials) }
    end
  end

  threads.flat_map(&:value).sort_by { |result| result[:key] }
end

def print_text_matrix(model_results)
  return if model_results.empty?

  columns = CAPABILITY_COLUMN_ORDER.select { |cap| model_results.any? { |result| result[:capabilities].key?(cap) } }
  key_width = (["MODEL".length] + model_results.map { |result| result[:key].length }).max
  column_widths = columns.to_h { |cap| [cap, [cap.length, 7].max] }

  puts "MODEL".ljust(key_width) + "  " + columns.map { |cap| cap.upcase.ljust(column_widths[cap]) }.join("  ")

  model_results.each do |result|
    row = columns.map do |cap|
      cell = result[:capabilities][cap]
      (cell ? status_label(cell[:status]) : "-").ljust(column_widths[cap])
    end.join("  ")

    puts result[:key].ljust(key_width) + "  " + row
  end

  details = model_results.flat_map do |result|
    result[:capabilities].filter_map do |cap, cell|
      next if cell[:status] == :pass

      "  #{result[:key]} #{cap}: #{status_label(cell[:status])} #{cell[:detail]}"
    end
  end

  return if details.empty?

  puts
  puts "Details:"
  details.each { |line| puts line }
end

def print_json_results(model_results)
  payload = model_results.map do |result|
    {
      "key" => result[:key],
      "explicit" => result[:explicit],
      "capabilities" => result[:capabilities].transform_values { |cell| { "status" => cell[:status].to_s, "detail" => cell[:detail] } }
    }
  end

  puts JSON.pretty_generate(payload)
end

options = {
  only: nil,
  skip: [],
  stale_days: nil,
  record: false,
  strict: false,
  format: "text",
  iterations: 1,
  batch_timeout: 600,
  list: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/smoke <selectors...> [options]"

  opts.on("--only CAP[,CAP]", "Restrict the run to these capabilities") do |value|
    options[:only] = value.split(",").map(&:strip)
  end

  opts.on("--skip CAP[,CAP]", "Skip these capabilities") do |value|
    options[:skip] = value.split(",").map(&:strip)
  end

  opts.on("--stale DAYS", Integer, "Also include models with unverified or stale capabilities") do |value|
    options[:stale_days] = value
  end

  opts.on("--record", "Write verified results back into model_manifest/*.yml") do
    options[:record] = true
  end

  opts.on("--strict", "Do not tolerate SKIP/TIMEOUT on pattern-selected (non-explicit) models") do
    options[:strict] = true
  end

  opts.on("--format FORMAT", %w[text json], "Output format: text (default) or json") do |value|
    options[:format] = value
  end

  opts.on("--iterations N", Integer, "Iterations per path for streaming_tool_calls (default: 1)") do |value|
    options[:iterations] = value
  end

  opts.on("--batch-timeout SECONDS", Integer, "Seconds to poll batch_inference before giving up (default: 600)") do |value|
    options[:batch_timeout] = value
  end

  opts.on("--list", "List all registered model keys (LLM + embedding) and exit") do
    options[:list] = true
  end
end

selectors = parser.parse(ARGV).map(&:to_s).map(&:strip).reject(&:blank?)

if options[:list]
  puts (Raif.available_llm_keys + Raif.available_embedding_model_keys).map(&:to_s).sort
  exit 0
end

Smoke::Credentials.configure_raif!

manifest = Raif::ModelManifest.load
selection = Smoke::Selection.resolve(
  selectors, manifest.llm_entries, stale_days: options[:stale_days], embedding_entries: manifest.embedding_entries
)

if selection[:unknown].any?
  puts "Unknown selector(s): #{selection[:unknown].join(", ")}"
  puts "Run `bin/smoke --list` to see valid model keys."
  exit 1
end

if selectors.empty? && options[:stale_days].nil?
  puts parser
  puts
  puts "Examples:"
  puts "  bin/smoke anthropic_claude_5_sonnet"
  puts "  bin/smoke anthropic bedrock"
  puts "  bin/smoke ALL"
  puts "  bin/smoke --stale 30"
  puts "  bin/smoke x_ai --only batch_inference"
  puts "  bin/smoke anthropic_claude_5_sonnet --record"
  exit 1
end

model_results = run_all(selection, options)

if options[:format] == "json"
  print_json_results(model_results)
else
  print_text_matrix(model_results)
end

exit Smoke::Policy.exit_code(model_results, explicit_keys: selection[:explicit_keys], strict: options[:strict])
