# frozen_string_literal: true

# See bin/smoke for usage instructions.
#
# Runs the smoke capability checks (script/smoke/checks.rb) against the live models described in
# model_manifest/*.rb, using script/smoke/selection.rb to resolve CLI selectors, script/smoke/credentials.rb
# to gate providers on configured credentials, script/smoke/options.rb to validate CLI options,
# script/smoke/policy.rb to decide the process exit code, script/smoke/observation_recorder.rb (with
# --record) to record successful smoke observations in model_smoke_results/*.json, and
# script/smoke/{terminal,report}.rb for colored output, the confirmation prompt, and the results matrix.

require "optparse"
require "json"
require "raif/model_manifest"
require "raif/model_manifest/smoke_observations"
require_relative "smoke/selection"
require_relative "smoke/credentials"
require_relative "smoke/checks"
require_relative "smoke/policy"
require_relative "smoke/observation_recorder"
require_relative "smoke/terminal"
require_relative "smoke/report"
require_relative "smoke/options"

# rails runner buffers stdout in blocks when it isn't a tty (e.g. piped to head or a log file),
# which would otherwise hold back both the final matrix and anything printed along the way.
$stdout.sync = true

EMBEDDING_PROMPT = "hello smoke"

# Where --record writes durable smoke observations; also the directory Raif::ModelManifest::SmokeObservations reads back.
MODEL_SMOKE_RESULTS_DIR = Raif::Engine.root.join("model_smoke_results")

# Guards the stderr progress lines emitted by provider threads in run_all so concurrent
# writes don't interleave mid-line.
PROGRESS_MUTEX = Mutex.new

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

  { key: key, explicit: explicit, capabilities: capabilities }
end

def run_all(selection, options)
  entries = selection[:entries] + selection[:embedding_entries]

  threads = entries.group_by(&:provider_name).map do |provider_name, group|
    Thread.new do
      # Unlike Raif::Evals::WorkerPool, no connection_pool.with_connection here: that would pin a
      # connection per provider for the whole run, and the manifest can hold more providers than
      # the dummy app's default pool of 5. The short writes in Raif::Llm#chat check their
      # connection back in after each query, so the pool is shared fine without it.
      Rails.application.executor.wrap do
        PROGRESS_MUTEX.synchronize do
          warn Smoke::Terminal.paint("progress: starting #{provider_name} (#{group.size} models)", :bold, stream: $stderr)
        end

        missing_credentials = Smoke::Credentials.missing_for?(provider_name)

        if missing_credentials
          instructions = Smoke::Credentials.instructions_for(provider_name)
          PROGRESS_MUTEX.synchronize { warn "NOTE #{provider_name}: missing credentials, skipping #{group.size} model(s). #{instructions}" }
        end

        group.map do |entry|
          result = run_entry(entry, options, selection[:explicit_keys], missing_credentials: missing_credentials)
          PROGRESS_MUTEX.synchronize { warn "progress: #{result[:key]} #{Smoke::Report.progress_summary(result[:capabilities])}" }
          result
        end
      end
    end
  end

  threads.flat_map(&:value).sort_by { |result| result[:key] }
end

# --only and --skip take the same precedence here as in Smoke::Checks.run_for: --only decides
# inclusion outright when given, otherwise --skip does. batch_inference alone justifies asking,
# since it's a live, minutes-long check (see script/smoke/checks.rb).
def batch_included?(options)
  options[:only].nil? ? !options[:skip].include?("batch_inference") : options[:only].include?("batch_inference")
end

def confirmation_needed?(entries, options)
  return false unless $stdin.tty?
  return false if options[:yes]

  entries.size > 10 || batch_included?(options)
end

def print_confirmation_preview(entries, options)
  warn "#{entries.size} model(s) selected:"
  entries.group_by(&:provider_name).sort_by { |provider_name, _group| provider_name }.each do |provider_name, group|
    warn "  #{provider_name}: #{group.size}"
  end

  warn "batch_inference checks poll up to #{options[:batch_timeout]}s per model" if batch_included?(options)

  return unless options[:record]

  warn "--record will record successful smoke observations in model_smoke_results/"
end

# Blocks on a [y/N] prompt before a large or batch_inference-including run, since both make real,
# possibly slow or costly API calls. Skipped entirely off a tty (CI, piped input) so automation
# never hangs waiting on stdin.
def confirm_run!(entries, options)
  return unless confirmation_needed?(entries, options)

  print_confirmation_preview(entries, options)
  return if Smoke::Terminal.confirm?("Continue?")

  warn "Aborted."
  exit 1
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
  list: false,
  yes: false
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

  opts.on("--record", "Record successful smoke observations in model_smoke_results/") do
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

  opts.on("--yes", "Skip the pre-run confirmation prompt for large or batch_inference-including runs") do
    options[:yes] = true
  end

  opts.on("--no-color", "Disable colored output") do
    Smoke::Terminal.disable_colors!
  end
end

selectors = parser.parse(ARGV).map(&:to_s).map(&:strip).reject(&:blank?)

Smoke.validate_options!(options, parser)

if options[:list]
  puts (Raif.available_llm_keys + Raif.available_embedding_model_keys).map(&:to_s).sort
  exit 0
end

Smoke::Credentials.configure_raif!

# The runner must exercise the real streaming path, not have it silently swapped out by the
# streaming_unsupported_model_keys fallback. Cleared once here (the process exits after this
# run) rather than saved/restored per-check, since per-provider threads (see run_all) would
# race each other's restore.
Raif.config.streaming_unsupported_model_keys = []

manifest = Raif::ModelManifest.load
observations = Raif::ModelManifest::SmokeObservations.load
selection = Smoke::Selection.resolve(
  selectors, manifest.llm_entries, stale_days: options[:stale_days], embedding_entries: manifest.embedding_entries,
  observations: observations
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

confirm_run!(selection[:entries] + selection[:embedding_entries], options)

run_started_at = Time.now
model_results = run_all(selection, options)
elapsed_seconds = Time.now - run_started_at

if options[:record]
  entries_by_key = (selection[:entries] + selection[:embedding_entries]).index_by { |entry| entry.key.to_s }
  Smoke::ObservationRecorder.record_all!(model_results, entries_by_key: entries_by_key, dir: MODEL_SMOKE_RESULTS_DIR, now: Time.now.utc)
end

exit_code = Smoke::Policy.exit_code(model_results, explicit_keys: selection[:explicit_keys], strict: options[:strict])

if options[:format] == "json"
  Smoke::Report.print_json_results(model_results)
else
  Smoke::Report.print_text_matrix(model_results)
  Smoke::Report.print_summary_footer(model_results, elapsed_seconds, exit_code)
end

exit exit_code
