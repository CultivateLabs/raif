# frozen_string_literal: true

# See bin/probe_bedrock_stream_transport for usage.
#
# Bypasses Raif and hits Bedrock's Converse + ConverseStream APIs directly via
# the AWS SDK to determine whether the streaming transport itself corrupts
# tool_use deltas for a given Bedrock model.
#
# This is the lower-level companion to script/probe_streaming_tool_calls.rb:
# if that script shows streaming/non-streaming divergence inside Raif, this one
# isolates whether the corruption is happening at the AWS SDK / service layer
# (i.e. before Raif's accumulator runs).
#
# For each iteration, the script:
#   1. Calls Converse (non-streaming) and reports the parsed tool_use.input.
#   2. Calls ConverseStream (streaming), prints every content_block_delta
#      tool_use chunk, concatenates them, and tries to JSON.parse the result.
#
# A NO from the JSON parser on a buffer that came directly off the SDK proves
# the bug is below Raif and is worth filing with AWS support.

require "optparse"
require "aws-sdk-bedrockruntime"
require "json"

DEFAULT_PROMPT = "Use the wikipedia_search tool to look up the current Prime Minister of Canada."

options = {
  prompt: DEFAULT_PROMPT,
  iterations: 1
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/probe_bedrock_stream_transport bedrock_model_key [bedrock_model_key ...] [options]"

  opts.on("-p", "--prompt PROMPT", "Tool-call prompt to send (default: a Wikipedia search question)") do |value|
    options[:prompt] = value
  end

  opts.on("-n", "--iterations N", Integer, "Iterations per model (default: 1)") do |value|
    options[:iterations] = value
  end
end

model_keys = parser.parse(ARGV).map(&:to_s).map(&:strip).reject(&:blank?)
if model_keys.empty?
  puts parser
  puts
  puts "Examples:"
  puts "  bin/probe_bedrock_stream_transport bedrock_gpt_oss_120b"
  puts "  bin/probe_bedrock_stream_transport bedrock_gpt_oss_120b bedrock_claude_4_6_sonnet --iterations 5"
  exit 1
end

ENV["AWS_EC2_METADATA_DISABLED"] ||= "true"
Raif.config.bedrock_models_enabled = true
region = ENV["AWS_REGION"].presence || Raif.config.aws_bedrock_region.presence || "us-east-1"
Raif.config.aws_bedrock_region = region

available = Raif.available_llm_keys.map(&:to_s)
unknown = model_keys - available
if unknown.any?
  puts "Unknown model key(s): #{unknown.join(", ")}"
  puts "Run `bin/probe_streaming_tool_calls --list` to see registered model keys."
  exit 1
end

non_bedrock = model_keys.reject { |k| k.start_with?("bedrock_") }
if non_bedrock.any?
  puts "This script only supports Bedrock model keys; got: #{non_bedrock.join(", ")}"
  exit 1
end

client = Aws::BedrockRuntime::Client.new(region: region)

system_prompt_text = "You are a research assistant. When asked a factual question you MUST call the " \
  "wikipedia_search tool with a single short query string. Do not answer from your own knowledge."

system = [{ text: system_prompt_text }]

messages = [{
  role: "user",
  content: [{ text: options.fetch(:prompt) }]
}]

tool_config = {
  tools: [{
    tool_spec: {
      name: "wikipedia_search",
      description: "Search Wikipedia for information.",
      input_schema: {
        json: {
          "type" => "object",
          "properties" => { "query" => { "type" => "string" } },
          "required" => ["query"]
        }
      }
    }
  }]
}

def converse_once(client, model_id, system, messages, tool_config)
  resp = client.converse(
    model_id: model_id,
    system: system,
    messages: messages,
    tool_config: tool_config
  )
  tool_use_block = resp.output.message.content.find(&:tool_use)&.tool_use
  tool_use_block ? { name: tool_use_block.name, input: tool_use_block.input } : nil
end

def converse_stream_once(client, model_id, system, messages, tool_config)
  buffer = +""
  chunks = []
  tool_use_started = false

  client.converse_stream(
    model_id: model_id,
    system: system,
    messages: messages,
    tool_config: tool_config
  ) do |stream|
    stream.on_event do |event|
      case event.event_type
      when :content_block_start
        tool_use_started = true if event.start&.tool_use
      when :content_block_delta
        delta = event.delta
        next unless delta&.tool_use && tool_use_started

        chunk = delta.tool_use.input.to_s
        chunks << chunk
        buffer << chunk
      end
    end
  end

  parsed =
    begin
      JSON.parse(buffer) if buffer.length.positive?
    rescue JSON::ParserError
      nil
    end

  { chunks: chunks, buffer: buffer, parsed: parsed }
end

model_keys.each do |model_key|
  config = Raif.llm_config(model_key.to_sym)
  model_id = config[:api_name]
  puts
  puts "=== #{model_key} (api_name=#{model_id.inspect}) ==="

  options[:iterations].times do |i|
    puts "  iter #{i + 1}/#{options[:iterations]}:"

    begin
      ns = converse_once(client, model_id, system, messages, tool_config)
      if ns
        ns_ok = ns[:input].is_a?(Hash)
        puts "    [non-stream] tool=#{ns[:name]} input_class=#{ns[:input].class.name} ok=#{ns_ok}"
        puts "                 input=#{ns[:input].inspect}" unless ns_ok
      else
        puts "    [non-stream] no tool_use block in response"
      end
    rescue StandardError => e
      puts "    [non-stream] ERROR #{e.class}: #{e.message}"
    end

    begin
      st = converse_stream_once(client, model_id, system, messages, tool_config)
      parseable = !st[:parsed].nil?
      puts "    [stream]     chunks=#{st[:chunks].size} buffer_chars=#{st[:buffer].length} json_parseable=#{parseable}"
      st[:chunks].each_with_index do |chunk, idx|
        puts "                 chunk[#{idx}]=#{chunk.inspect}"
      end
      puts "                 reconstructed=#{st[:buffer].inspect}"
      puts "                 parsed=#{st[:parsed].inspect}" if parseable
    rescue StandardError => e
      puts "    [stream]     ERROR #{e.class}: #{e.message}"
    end
  end
end
