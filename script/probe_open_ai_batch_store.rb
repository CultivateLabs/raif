# frozen_string_literal: true

# See bin/probe_open_ai_batch_store for usage instructions.
#
# The synchronous Responses path is covered by unit specs, which assert the
# request body Raif builds. The Batch API takes that same body inside a JSONL
# line and validates it asynchronously, so a parameter OpenAI rejects there
# surfaces as a per-entry error in the batch's error file rather than as a
# response to any call Raif makes. Only a live batch shows that.
#
# Three things are checked, in increasing strength:
#   1. `store` is present in the input file OpenAI actually holds.
#   2. Every entry came back completed rather than errored.
#   3. Retrieving the response by id 404s, which is what store: false means.

require "optparse"
require "json"

# The probe waits minutes between prints. Block-buffered stdout would hold all
# of it until exit, so progress would be invisible exactly when it matters.
$stdout.sync = true

# AR-backed source for the probe. Raif::ModelCompletion's polymorphic
# `belongs_to :source` needs a real ActiveRecord class, and the batch path is
# reached through Raif::Task.build_for_batch.
class ProbeOpenAiBatchStoreTask < Raif::Task
  def build_prompt
    "Reply with exactly: ok"
  end
end

DEFAULT_MODEL_KEY = "open_ai_responses_gpt_5_4_nano"

options = {
  model_key: DEFAULT_MODEL_KEY,
  store: false,
  entries: 2,
  poll: 20,
  timeout: 900,
  resume: nil,
  cancel_on_timeout: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/probe_open_ai_batch_store [options]"

  opts.on("-m", "--model KEY", "Raif model key to batch (default: #{DEFAULT_MODEL_KEY})") do |value|
    options[:model_key] = value
  end

  opts.on("--store", "Send store: true instead, as a control run") do
    options[:store] = true
  end

  opts.on("-n", "--entries N", Integer, "Entries in the batch (default: #{options[:entries]})") do |value|
    options[:entries] = value
  end

  opts.on("--poll SECONDS", Integer, "Seconds between status polls (default: #{options[:poll]})") do |value|
    options[:poll] = value
  end

  opts.on("--timeout SECONDS", Integer, "Give up waiting after this long (default: #{options[:timeout]})") do |value|
    options[:timeout] = value
  end

  opts.on("--resume BATCH_ID", Integer, "Poll an existing Raif::ModelCompletionBatch instead of submitting") do |value|
    options[:resume] = value
  end

  opts.on("--cancel-on-timeout", "Ask OpenAI to cancel the batch if the timeout is reached") do
    options[:cancel_on_timeout] = true
  end
end

parser.parse!(ARGV)

if ENV["OPENAI_API_KEY"].blank?
  puts "SKIP missing credentials. Set OPENAI_API_KEY."
  exit 1
end

Raif.config.llm_api_requests_enabled = true
Raif.config.open_ai_models_enabled = true
Raif.config.open_ai_api_key = ENV.fetch("OPENAI_API_KEY")
Raif.config.open_ai_store_responses = options[:store]

unless Raif.available_llm_keys.map(&:to_s).include?(options[:model_key])
  puts "Unknown model key: #{options[:model_key]}"
  exit 1
end

# The probe reads OpenAI's own copy of what it received, so it needs a
# connection of its own rather than the adapter's private one. No JSON response
# middleware: a batch file is JSONL, which a whole-body JSON parse rejects, and
# the retrieval check reads a status code rather than a body. No raise_error
# either - a 404 from the retrieval check is the result, not a failure.
def open_ai_connection
  @open_ai_connection ||= Faraday.new(url: Raif.config.open_ai_base_url) do |f|
    f.headers["Authorization"] = "Bearer #{Raif.config.open_ai_api_key}"
  end
end

def file_content(file_id)
  open_ai_connection.get("files/#{file_id}/content").body
end

def jsonl_lines(body)
  body.to_s.each_line.map(&:strip).reject(&:empty?).map { |line| JSON.parse(line) }
end

def report_input_file(batch)
  if batch.input_file_id.blank?
    puts "  input file: none recorded on the batch"
    return
  end

  entries = jsonl_lines(file_content(batch.input_file_id))
  sent = entries.map { |entry| entry.dig("body", "store") }.uniq

  puts "  input file #{batch.input_file_id}: #{entries.size} entries, store=#{sent.map(&:inspect).join(", ")}"
  puts "  first entry body: #{entries.first["body"].to_json}"
end

def completion_state(model_completion)
  return "COMPLETED" if model_completion.completed?
  return "FAILED" if model_completion.failed?

  model_completion.started_at.present? ? "IN PROGRESS" : "PENDING"
end

def report_results(batch)
  batch.raif_model_completions.order(:id).each do |mc|
    puts "  #{mc.batch_custom_id}: #{completion_state(mc)} " \
      "response_id=#{mc.response_id.inspect} raw_response=#{mc.raw_response.inspect}"
    puts "    failure: #{mc.failure_error} - #{mc.failure_reason}" if mc.failed?
  end
end

# Retrieving a stored response returns it; retrieving an unstored one 404s.
# This is the only check that asks OpenAI what it kept, rather than what we
# asked for or what it echoed back.
def report_retrieval(batch)
  batch.raif_model_completions.order(:id).each do |mc|
    if mc.response_id.blank?
      puts "  #{mc.batch_custom_id}: no response_id, nothing to retrieve"
      next
    end

    response = open_ai_connection.get("responses/#{mc.response_id}")
    verdict = case response.status
    when 404 then "404 - OpenAI did not retain it"
    when 200 then "200 - OpenAI RETAINED it"
    else "#{response.status} - unexpected"
    end

    puts "  #{mc.batch_custom_id}: GET responses/#{mc.response_id} -> #{verdict}"
  end
end

llm = Raif.llm(options[:model_key].to_sym)

batch = if options[:resume]
  Raif::ModelCompletionBatch.find(options[:resume])
else
  new_batch = llm.create_batch(completion_handler_class_name: "Raif::TaskBatchCompletionHandler")

  options[:entries].times do |index|
    ProbeOpenAiBatchStoreTask.build_for_batch(
      batch: new_batch,
      batch_custom_id: "probe_#{index + 1}",
      llm_model_key: options[:model_key]
    )
  end

  puts "Submitting Raif::ModelCompletionBatch ##{new_batch.id} " \
    "(#{options[:entries]} entries, model #{options[:model_key]}, store=#{options[:store]})"

  # enqueue_poll: false because this script is the poller. The dummy app's
  # queue adapter would otherwise own the schedule.
  new_batch.submit!(enqueue_poll: false)
  new_batch
end

batch.reload
puts "Provider batch #{batch.provider_batch_id.inspect}, status #{batch.status}"
report_input_file(batch)

deadline = Time.current + options[:timeout]
status = batch.status

until batch.terminal?
  if Time.current >= deadline
    puts "TIMEOUT after #{options[:timeout]}s. Batch is still #{batch.status}."

    if options[:cancel_on_timeout]
      puts "Cancelling."
      batch.cancel!
    else
      puts "Resume with: bin/probe_open_ai_batch_store --resume #{batch.id}"
    end

    exit 2
  end

  sleep options[:poll]
  status = batch.fetch_status!
  batch.reload
  puts "  #{Time.current.strftime("%H:%M:%S")} status=#{status} counts=#{batch.request_counts.to_json}"
end

puts "Batch ended with status #{batch.status}"
report_input_file(batch)

batch.fetch_results!
batch.reload

puts "Results:"
report_results(batch)

puts "Retrieval check:"
report_retrieval(batch)

completed = batch.raif_model_completions.select(&:completed?).size
total = batch.raif_model_completions.size

puts
puts "#{completed} of #{total} entries completed. store=#{options[:store]}."
exit(completed == total ? 0 : 1)
