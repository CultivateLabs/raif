# frozen_string_literal: true

# See bin/probe_structured_outputs for usage instructions.
#
# Sends a JSON-schema request to each selected model via Raif's normal
# `Llm#chat` and checks whether:
#   - the response is valid JSON
#   - the response matches the source task's `json_response_schema`
# Reports PASS / FAIL / ERR per model, mirroring `script/smoke_llm_models.rb`.

require "optparse"
require "json"

# AR-backed source for the probe. Polymorphic `belongs_to :source` on
# Raif::ModelCompletion needs a real ActiveRecord class. Use a Raif::Task
# subclass with a small fixed schema (joke + answer) — sufficient to verify
# JSON enforcement end-to-end without being domain-specific.
class ProbeStructuredOutputsTask < Raif::Task
  llm_response_format :json
  llm_temperature 0.75

  json_response_schema do
    string :joke
    string :answer
  end

  def build_prompt
    "Tell me a joke. Reply with a JSON object that has a 'joke' key and an 'answer' key. " \
      "Both values must be non-empty strings."
  end
end

PROBE_TASK_CLASS = ProbeStructuredOutputsTask
PROBE_PROMPT = "Tell me a joke. Reply with a JSON object that has a 'joke' key " \
  "and an 'answer' key. Both values must be non-empty strings."
PROBE_REQUIRED_KEYS = %w[joke answer].freeze

SELECTORS = {
  "anthropic" => ->(key) { key.start_with?("anthropic_") },
  "bedrock" => ->(key) { key.start_with?("bedrock_") },
  "open_ai" => ->(key) { key.start_with?("open_ai_") && !key.start_with?("open_ai_responses_") },
  "open_ai_responses" => ->(key) { key.start_with?("open_ai_responses_") },
  "open_router" => ->(key) { key.start_with?("open_router_") },
  "google" => ->(key) { key.start_with?("google_") },
  "x_ai" => ->(key) { key.start_with?("x_ai_") },
}.freeze

options = { list: false }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/probe_structured_outputs [ALL|provider|model_key ...] [--list]"

  opts.on("--list", "List all registered model keys and exit") do
    options[:list] = true
  end
end

selectors = parser.parse(ARGV).map(&:to_s).map(&:strip).reject(&:blank?)
if selectors.empty? && ENV["RAIF_PROBE_MODELS"].present?
  selectors = ENV["RAIF_PROBE_MODELS"].split(",").map(&:strip).reject(&:blank?)
end

if options[:list]
  puts Raif.available_llm_keys.map(&:to_s).sort
  exit 0
end

if selectors.empty?
  puts parser
  puts
  puts "Examples:"
  puts "  bin/probe_structured_outputs ALL"
  puts "  bin/probe_structured_outputs open_router"
  puts "  bin/probe_structured_outputs anthropic open_ai_responses"
  puts "  bin/probe_structured_outputs open_router_grok_4_20"
  exit 1
end

available_model_keys = Raif.available_llm_keys.map(&:to_s)
selected_keys = []
unknown = []

selectors.each do |selector|
  if selector.casecmp("ALL").zero?
    selected_keys.concat(available_model_keys)
    next
  end

  provider_selector = SELECTORS[selector]
  if provider_selector
    selected_keys.concat(available_model_keys.select(&provider_selector))
    next
  end

  if available_model_keys.include?(selector)
    selected_keys << selector
  else
    unknown << selector
  end
end

if unknown.any?
  puts "Unknown selector(s): #{unknown.join(", ")}"
  puts "Run `bin/probe_structured_outputs --list` to see valid model keys."
  exit 1
end

selected_keys = selected_keys.uniq
if selected_keys.empty?
  puts "No models selected."
  exit 1
end

Raif.config.llm_api_requests_enabled = true

if ENV["ANTHROPIC_API_KEY"].present?
  Raif.config.anthropic_models_enabled = true
  Raif.config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY")
end

if ENV["OPENAI_API_KEY"].present?
  Raif.config.open_ai_models_enabled = true
  Raif.config.open_ai_api_key = ENV.fetch("OPENAI_API_KEY")
end

if ENV["OPEN_ROUTER_API_KEY"].present? || ENV["OPENROUTER_API_KEY"].present?
  Raif.config.open_router_models_enabled = true
  Raif.config.open_router_api_key = ENV["OPEN_ROUTER_API_KEY"].presence || ENV["OPENROUTER_API_KEY"]
end

if ENV["GOOGLE_AI_API_KEY"].present? || ENV["GOOGLE_API_KEY"].present?
  Raif.config.google_models_enabled = true
  Raif.config.google_api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]
end

if ENV["XAI_API_KEY"].present? || ENV["X_AI_API_KEY"].present?
  Raif.config.x_ai_models_enabled = true
  Raif.config.x_ai_api_key = ENV["XAI_API_KEY"].presence || ENV["X_AI_API_KEY"]
end

# Avoid metadata service timeouts in local environments that do not expose IMDS.
ENV["AWS_EC2_METADATA_DISABLED"] ||= "true"
Raif.config.bedrock_models_enabled = true
Raif.config.aws_bedrock_region = ENV.fetch("AWS_REGION", "us-east-1")

def provider_for_model_key(model_key)
  case model_key
  when /\Aanthropic_/
    :anthropic
  when /\Abedrock_/
    :bedrock
  when /\Aopen_ai(_responses)?_/
    :open_ai
  when /\Aopen_router_/
    :open_router
  when /\Agoogle_/
    :google
  when /\Ax_ai_/
    :x_ai
  else
    :unknown
  end
end

def bedrock_credentials_present?
  return @bedrock_credentials_present unless @bedrock_credentials_present.nil?

  credentials = Aws::CredentialProviderChain.new.resolve
  @bedrock_credentials_present = credentials&.set? || false
rescue StandardError
  @bedrock_credentials_present = false
end

def missing_credentials_for_provider?(provider)
  case provider
  when :anthropic
    ENV["ANTHROPIC_API_KEY"].blank?
  when :bedrock
    !bedrock_credentials_present?
  when :open_ai
    ENV["OPENAI_API_KEY"].blank?
  when :open_router
    ENV["OPEN_ROUTER_API_KEY"].blank? && ENV["OPENROUTER_API_KEY"].blank?
  when :google
    ENV["GOOGLE_AI_API_KEY"].blank? && ENV["GOOGLE_API_KEY"].blank?
  when :x_ai
    ENV["XAI_API_KEY"].blank? && ENV["X_AI_API_KEY"].blank?
  else
    false
  end
end

def credential_instructions_for_provider(provider)
  case provider
  when :anthropic
    "Set ANTHROPIC_API_KEY."
  when :bedrock
    "Configure AWS credentials (AWS_PROFILE, AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY, or IAM role) and set AWS_REGION."
  when :open_ai
    "Set OPENAI_API_KEY."
  when :open_router
    "Set OPEN_ROUTER_API_KEY (or OPENROUTER_API_KEY)."
  when :google
    "Set GOOGLE_AI_API_KEY (or GOOGLE_API_KEY)."
  when :x_ai
    "Set XAI_API_KEY (or X_AI_API_KEY)."
  else
    "Configure credentials for this provider."
  end
end

probe_creator = Raif::TestUser.new(email: "probe@example.invalid")

selected_keys.each do |model_key|
  provider = provider_for_model_key(model_key)

  if missing_credentials_for_provider?(provider)
    instructions = credential_instructions_for_provider(provider)
    puts "SKIP #{model_key} missing credentials for #{provider} provider. #{instructions}"
    next
  end

  source = PROBE_TASK_CLASS.new(creator: probe_creator)

  begin
    model_completion = Raif.llm(model_key.to_sym).chat(
      message: PROBE_PROMPT,
      response_format: :json,
      source: source,
    )
  rescue StandardError => e
    puts "ERR  #{model_key} #{e.class}: #{e.message.to_s.first(180)}"
    next
  end

  # Surface which mechanism the request actually used so a passing
  # native-structured-outputs request is distinguishable from a passing
  # synthetic-tool fallback. `response_format_parameter` is set by each
  # provider's `build_request_parameters` (e.g. "json_schema" for native,
  # "json_object" for the OpenRouter no-schema fallback, nil if the
  # provider went down the json_response tool path).
  rfp = model_completion&.response_format_parameter || "json_response_tool"

  raw = model_completion&.raw_response
  if raw.blank?
    puts "FAIL #{model_key} response_format_parameter=#{rfp} valid_json=false reason=blank_response"
    next
  end

  parsed =
    begin
      JSON.parse(raw)
    rescue JSON::ParserError => e
      puts "FAIL #{model_key} response_format_parameter=#{rfp} valid_json=false parser_error=#{e.message.first(120).inspect}"
      next
    end

  unless parsed.is_a?(Hash)
    puts "FAIL #{model_key} response_format_parameter=#{rfp} valid_json=true matches_schema=false reason=root_not_object"
    next
  end

  returned_keys = parsed.keys
  missing = PROBE_REQUIRED_KEYS - returned_keys
  extra = returned_keys - PROBE_REQUIRED_KEYS
  values_ok = PROBE_REQUIRED_KEYS.all? { |k| parsed[k].is_a?(String) && !parsed[k].empty? }

  if missing.empty? && extra.empty? && values_ok
    puts "PASS #{model_key} response_format_parameter=#{rfp} valid_json=true matches_schema=true tokens=#{model_completion.total_tokens}"
  else
    parts = ["response_format_parameter=#{rfp} valid_json=true matches_schema=false"]
    parts << "missing=#{missing.inspect}" if missing.any?
    parts << "extra=#{extra.inspect}" if extra.any?
    parts << "value_types_invalid=true" unless values_ok
    puts "FAIL #{model_key} #{parts.join(" ")}"
  end
end
