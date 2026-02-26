# frozen_string_literal: true

require "optparse"

DEFAULT_PROMPT = "Reply with exactly: ok"

SELECTORS = {
  "anthropic" => ->(key) { key.start_with?("anthropic_") },
  "bedrock" => ->(key) { key.start_with?("bedrock_") },
  "open_ai" => ->(key) { key.start_with?("open_ai_") && !key.start_with?("open_ai_responses_") },
  "open_ai_responses" => ->(key) { key.start_with?("open_ai_responses_") },
  "open_router" => ->(key) { key.start_with?("open_router_") },
  "google" => ->(key) { key.start_with?("google_") }
}.freeze

options = {
  prompt: DEFAULT_PROMPT,
  list: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/smoke_llm_models [ALL|provider|model_key ...] [--prompt \"...\"] [--list]"

  opts.on("-p", "--prompt PROMPT", "Prompt to send to each model") do |value|
    options[:prompt] = value
  end

  opts.on("--list", "List all currently registered model keys") do
    options[:list] = true
  end
end

selectors = parser.parse(ARGV).map(&:to_s).map(&:strip).reject(&:blank?)
if selectors.empty? && ENV["RAIF_SMOKE_MODELS"].present?
  selectors = ENV["RAIF_SMOKE_MODELS"].split(",").map(&:strip).reject(&:blank?)
end

if options[:list]
  puts Raif.available_llm_keys.map(&:to_s).sort
  exit 0
end

if selectors.empty?
  puts parser
  puts
  puts "Examples:"
  puts "  bin/smoke_llm_models ALL"
  puts "  bin/smoke_llm_models anthropic bedrock"
  puts "  bin/smoke_llm_models anthropic_claude_4_6_opus bedrock_claude_4_6_opus"
  puts "  bin/smoke_llm_models open_ai_responses --prompt \"Reply with exactly: ping\""
  exit 1
end

available_model_keys = Raif.available_llm_keys.map(&:to_s)
selected_model_keys = []
unknown_selectors = []

selectors.each do |selector|
  if selector.casecmp("ALL").zero?
    selected_model_keys.concat(available_model_keys)
    next
  end

  provider_selector = SELECTORS[selector]
  if provider_selector
    selected_model_keys.concat(available_model_keys.select { |key| provider_selector.call(key) })
    next
  end

  if available_model_keys.include?(selector)
    selected_model_keys << selector
  else
    unknown_selectors << selector
  end
end

if unknown_selectors.any?
  puts "Unknown selector(s): #{unknown_selectors.join(', ')}"
  puts "Run `bin/smoke_llm_models --list` to see valid model keys."
  exit 1
end

selected_model_keys = selected_model_keys.uniq
if selected_model_keys.empty?
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
  Raif.config.open_ai_embedding_models_enabled = true
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
  else
    "Configure credentials for this provider."
  end
end

selected_model_keys.each do |model_key|
  provider = provider_for_model_key(model_key)

  if missing_credentials_for_provider?(provider)
    instructions = credential_instructions_for_provider(provider)
    puts "SKIP #{model_key} missing credentials for #{provider} provider. #{instructions}"
    next
  end

  begin
    model_completion = Raif.llm(model_key.to_sym).chat(message: options.fetch(:prompt))
    puts "PASS #{model_key} api=#{model_completion.model_api_name} tokens=#{model_completion.total_tokens} text=#{model_completion.raw_response.inspect}"
  rescue StandardError => e
    puts "FAIL #{model_key} #{e.class}: #{e.message}"
  end
end
