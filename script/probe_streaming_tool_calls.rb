# frozen_string_literal: true

# See bin/probe_streaming_tool_calls for usage.
#
# Probes whether a model's streaming path produces well-formed tool_use
# arguments by running the same tool-call prompt against the model in both
# streaming and non-streaming modes and comparing parsed results.
#
# Useful when investigating reports of corrupt/empty/malformed tool arguments
# coming back from a particular provider+model combination — a difference
# between the two paths is strong evidence the streaming transport (not the
# model itself) is at fault. The companion script
# script/probe_bedrock_stream_transport.rb can confirm that Bedrock-side.

require "optparse"

DEFAULT_PROMPT = "Use the wikipedia_search tool to look up the current Prime Minister of Canada."

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
  iterations: 5,
  list: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/probe_streaming_tool_calls [provider|model_key ...] [options]"

  opts.on("-p", "--prompt PROMPT", "Tool-call prompt to send (default: a Wikipedia search question)") do |value|
    options[:prompt] = value
  end

  opts.on("-n", "--iterations N", Integer, "Iterations per model per path (default: 5)") do |value|
    options[:iterations] = value
  end

  opts.on("--list", "List all currently registered model keys") do
    options[:list] = true
  end
end

selectors = parser.parse(ARGV).map(&:to_s).map(&:strip).reject(&:blank?)

if options[:list]
  puts Raif.available_llm_keys.map(&:to_s).sort
  exit 0
end

if selectors.empty?
  puts parser
  puts
  puts "Examples:"
  puts "  bin/probe_streaming_tool_calls bedrock_gpt_oss_120b"
  puts "  bin/probe_streaming_tool_calls bedrock_gpt_oss_120b anthropic_claude_4_6_sonnet --iterations 10"
  puts "  bin/probe_streaming_tool_calls bedrock --prompt \"Use wikipedia_search to look up Tokyo.\""
  exit 1
end

available_model_keys = Raif.available_llm_keys.map(&:to_s)
selected_model_keys = []
unknown_selectors = []

selectors.each do |selector|
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
  puts "Unknown selector(s): #{unknown_selectors.join(", ")}"
  puts "Run `bin/probe_streaming_tool_calls --list` to see valid model keys."
  exit 1
end

selected_model_keys = selected_model_keys.uniq
if selected_model_keys.empty?
  puts "No models selected."
  exit 1
end

# Don't let the streaming-fallback safety net hide the streaming path —
# the whole point of this probe is to exercise it.
Raif.config.streaming_unsupported_model_keys = []
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

ENV["AWS_EC2_METADATA_DISABLED"] ||= "true"
Raif.config.bedrock_models_enabled = true
Raif.config.aws_bedrock_region = ENV.fetch("AWS_REGION", "us-east-1")

TOOL = Raif::ModelTools::WikipediaSearch

def classify(model_completion)
  tool_calls = model_completion.response_tool_calls || []
  tool_call = tool_calls.first
  return [:no_tool_call, nil] if tool_call.nil?

  arguments = tool_call["arguments"]
  return [:ok, arguments] if arguments.is_a?(Hash)

  [:malformed, arguments]
end

def run_completion(model_key, prompt, stream:)
  llm = Raif.llm(model_key.to_sym)
  if stream
    llm.chat(message: prompt, available_model_tools: [TOOL]) { |_delta, _full, _completion| nil }
  else
    llm.chat(message: prompt, available_model_tools: [TOOL])
  end
end

results = {}

selected_model_keys.each do |model_key|
  puts
  puts "=== #{model_key} ==="
  results[model_key] = { stream: [], non_stream: [] }

  options[:iterations].times do |i|
    [:non_stream, :stream].each do |path|
      stream_flag = path == :stream
      label = stream_flag ? "stream    " : "non-stream"
      begin
        mc = run_completion(model_key, options[:prompt], stream: stream_flag)
        status, arguments = classify(mc)
        results[model_key][path] << status
        line = "  iter #{i + 1} [#{label}] mc=#{mc.id} status=#{status}"
        if status == :malformed
          line << " arguments_class=#{arguments.class.name} preview=#{arguments.to_s[0, 120].inspect}"
        end
        puts line
      rescue StandardError => e
        results[model_key][path] << :error
        puts "  iter #{i + 1} [#{label}] ERROR #{e.class}: #{e.message}"
      end
    end
  end
end

puts
puts "=== summary ==="
printf("%-40s  %-25s  %-25s\n", "model", "non-streaming", "streaming")
results.each do |model_key, paths|
  ns = paths[:non_stream]
  st = paths[:stream]
  format_counts = ->(arr) do
    total = arr.size
    by = arr.tally
    "ok=#{by[:ok] || 0}/#{total} malformed=#{by[:malformed] || 0} no_tool=#{by[:no_tool_call] || 0} error=#{by[:error] || 0}"
  end
  printf("%-40s  %-25s  %-25s\n", model_key, format_counts.call(ns), format_counts.call(st))
end
