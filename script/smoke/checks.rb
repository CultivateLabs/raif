# frozen_string_literal: true

require "json"

# Runs the smoke capability checks for a single Raif::ModelManifest::Entry against its live
# Raif::Llm adapter. Requires Raif (and the dummy/host Rails app) already booted -- like
# Smoke::Credentials, this only references Raif.llm / Raif.llm_config / ActiveRecord models
# inside method bodies, so the file itself loads standalone.
#
# Every check rescues StandardError to a uniform { status: :fail, detail: "Class: message" }
# result: a live API call can fail in ways specific to each provider (timeouts, auth errors,
# malformed payloads), and the caller (bin/smoke) just needs a status/detail pair to report,
# not a raised exception to rescue itself.
module Smoke
  module Checks
    NONCE = "RAIF-SMOKE-7391"

    IMAGE_FIXTURE = "spec/fixtures/smoke/nonce.png"
    PDF_FIXTURE = "spec/fixtures/smoke/nonce.pdf"

    # Capabilities where a claimed-false verdict is treated as a real assertion about the
    # model (the provider genuinely can't do this) rather than something worth spending a
    # live request on to double-check. temperature/structured_outputs aren't in this set:
    # they're cheap enough (a single extra chat call) that Smoke::Checks probes the
    # claimed-false direction anyway, via a force-enabled rebuild of the llm, so a stale
    # manifest claim gets caught instead of silently trusted.
    EXPENSIVE_CLAIMED_FALSE_SKIPPABLE = %w[
      batch_inference images pdfs streaming streaming_tool_calls native_tool_use provider_managed_tools
    ].freeze

    COMPLETION_PROMPT = "Reply with exactly: ok"
    TOOL_CALL_PROMPT = "Use the wikipedia_search tool to look up the current Prime Minister of Canada."

    STRUCTURED_OUTPUTS_PROMPT = "Tell me a joke. Reply with a JSON object that has a 'joke' key " \
      "and an 'answer' key. Both values must be non-empty strings."
    STRUCTURED_OUTPUTS_REQUIRED_KEYS = %w[joke answer].freeze

    # AR-backed source for the structured_outputs check. Polymorphic `belongs_to :source` on
    # Raif::ModelCompletion needs a real ActiveRecord class; a Raif::Task subclass with a
    # small fixed schema (joke + answer) is sufficient to verify JSON enforcement end-to-end
    # without being domain-specific. Ported from script/probe_structured_outputs.rb.
    class StructuredOutputsProbeTask < Raif::Task
      llm_response_format :json
      llm_temperature 0.75

      json_response_schema do
        string :joke
        string :answer
      end

      def build_prompt
        STRUCTURED_OUTPUTS_PROMPT
      end
    end

    # entry - a Raif::ModelManifest::Entry.
    # only - nil, or a capability name (String/Symbol) or Array of them: restricts the run to
    #   just these capabilities (and, for an expensive claimed-false capability, is the only
    #   way to force it to run at all).
    # skip - capability names to skip; each still appears in the result with status: :skip, so
    #   the caller can tell "skipped on purpose" apart from "omitted as claimed-false expensive".
    # iterations - per-path iteration count for streaming_tool_calls.
    # batch_timeout - seconds to poll batch_inference before giving up with status: :timeout.
    #
    # Returns { "capability" => { status:, detail: } } for the capabilities that ran or were
    # explicitly skipped. A claimed-false expensive capability not named in `only` is omitted
    # entirely rather than appearing with any status.
    def self.run_for(entry, only: nil, skip: [], iterations: 1, batch_timeout: 600)
      only_list = only.nil? ? nil : Array(only).map(&:to_s)
      skip_list = Array(skip).map(&:to_s)

      candidates = entry.smokable_capabilities
      candidates &= only_list if only_list

      results = {}

      candidates.each do |capability|
        if skip_list.include?(capability)
          results[capability] = { status: :skip, detail: "skipped via --skip" }
          next
        end

        claimed = entry.claimed_value(capability)
        explicitly_requested = !!only_list&.include?(capability)
        next if !claimed && EXPENSIVE_CLAIMED_FALSE_SKIPPABLE.include?(capability) && !explicitly_requested

        results[capability] = run_check(
          entry, capability, claimed: claimed, iterations: iterations, batch_timeout: batch_timeout, only_list: only_list
        )
      end

      results
    end

    def self.run_check(entry, capability, claimed:, iterations:, batch_timeout:, only_list:)
      case capability
      when "completion" then check_completion(entry)
      when "temperature" then check_temperature(entry, claimed: claimed)
      when "structured_outputs" then check_structured_outputs(entry, claimed: claimed)
      when "native_tool_use" then check_native_tool_use(entry)
      when "streaming" then check_streaming(entry)
      when "streaming_tool_calls" then check_streaming_tool_calls(entry, iterations: iterations)
      when "batch_inference" then check_batch_inference(entry, batch_timeout: batch_timeout)
      when "images" then check_images(entry)
      when "pdfs" then check_pdfs(entry)
      when "provider_managed_tools" then check_provider_managed_tools(entry, only_list: only_list)
      else
        { status: :fail, detail: "no smoke check implemented for #{capability}" }
      end
    end
    private_class_method :run_check

    def self.check_completion(entry)
      llm = Raif.llm(entry.key)
      model_completion = llm.chat(message: COMPLETION_PROMPT)
      text = response_text(model_completion)
      { status: text.downcase.include?("ok") ? :pass : :fail, detail: text.first(180) }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.check_temperature(entry, claimed:)
      if claimed
        model_completion = Raif.llm(entry.key).chat(message: COMPLETION_PROMPT, temperature: 0.2)
        { status: :pass, detail: response_text(model_completion).first(180) }
      else
        probe_claimed_false_direction(entry, :supports_temperature) do |llm|
          llm.chat(message: COMPLETION_PROMPT, temperature: 0.2)
          { status: :note, detail: "claimed unsupported but appears to work" }
        end
      end
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.check_structured_outputs(entry, claimed:)
      if claimed
        run_structured_outputs_probe(Raif.llm(entry.key))
      else
        probe_claimed_false_direction(entry, :supports_structured_outputs) do |llm|
          result = run_structured_outputs_probe(llm)
          if result[:status] == :pass && result[:detail] == "native"
            { status: :note, detail: "claimed unsupported but appears to work" }
          else
            result
          end
        end
      end
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.run_structured_outputs_probe(llm)
      source = StructuredOutputsProbeTask.new(creator: smoke_test_user)
      model_completion = llm.chat(message: STRUCTURED_OUTPUTS_PROMPT, response_format: :json, source: source)

      raw = model_completion&.raw_response
      return { status: :fail, detail: "blank response" } if raw.blank?

      parsed = JSON.parse(raw)
      return { status: :fail, detail: "response root was not a JSON object" } unless parsed.is_a?(Hash)

      missing = STRUCTURED_OUTPUTS_REQUIRED_KEYS - parsed.keys
      extra = parsed.keys - STRUCTURED_OUTPUTS_REQUIRED_KEYS
      values_ok = STRUCTURED_OUTPUTS_REQUIRED_KEYS.all? { |k| parsed[k].is_a?(String) && !parsed[k].empty? }

      if missing.empty? && extra.empty? && values_ok
        native = model_completion.response_format_parameter.present?
        { status: :pass, detail: native ? "native" : "json_response_tool" }
      else
        parts = []
        parts << "missing=#{missing.inspect}" if missing.any?
        parts << "extra=#{extra.inspect}" if extra.any?
        parts << "invalid value types" unless values_ok
        { status: :fail, detail: parts.join(", ").first(180) }
      end
    rescue JSON::ParserError => e
      { status: :fail, detail: "invalid JSON: #{e.message.to_s.first(140)}" }
    end
    private_class_method :run_structured_outputs_probe

    def self.check_native_tool_use(entry)
      model_completion = Raif.llm(entry.key).chat(
        message: TOOL_CALL_PROMPT,
        available_model_tools: [Raif::ModelTools::WikipediaSearch],
        tool_choice: Raif::ModelTools::WikipediaSearch.to_s
      )
      arguments = model_completion&.response_tool_calls&.first&.dig("arguments")
      { status: arguments.is_a?(Hash) ? :pass : :fail, detail: arguments.inspect.first(180) }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    # Clears Raif.config.streaming_unsupported_model_keys around the call (so the fallback
    # safety net can't hide the very path this check exercises) and always restores the
    # prior value, even if the check raises.
    def self.check_streaming(entry)
      previous_unsupported = Raif.config.streaming_unsupported_model_keys
      Raif.config.streaming_unsupported_model_keys = []

      llm = Raif.llm(entry.key)
      deltas = 0
      streamed = llm.chat(message: COMPLETION_PROMPT) { |_model_completion, _delta, _event| deltas += 1 }
      unstreamed = llm.chat(message: COMPLETION_PROMPT)

      streamed_ok = response_text(streamed).downcase.include?("ok")
      unstreamed_ok = response_text(unstreamed).downcase.include?("ok")
      pass = streamed_ok && unstreamed_ok && deltas > 0

      { status: pass ? :pass : :fail, detail: "deltas=#{deltas} streamed_ok=#{streamed_ok} unstreamed_ok=#{unstreamed_ok}" }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    ensure
      Raif.config.streaming_unsupported_model_keys = previous_unsupported
    end

    def self.check_streaming_tool_calls(entry, iterations:)
      previous_unsupported = Raif.config.streaming_unsupported_model_keys
      Raif.config.streaming_unsupported_model_keys = []

      llm = Raif.llm(entry.key)
      tool = Raif::ModelTools::WikipediaSearch
      streamed_statuses = []
      unstreamed_statuses = []

      iterations.times do
        unstreamed_mc = llm.chat(message: TOOL_CALL_PROMPT, available_model_tools: [tool])
        unstreamed_statuses << classify_tool_call(unstreamed_mc)

        streamed_mc = llm.chat(message: TOOL_CALL_PROMPT, available_model_tools: [tool]) { |_model_completion, _delta, _event| nil }
        streamed_statuses << classify_tool_call(streamed_mc)
      end

      pass = streamed_statuses.all? { |status| status == :ok }
      { status: pass ? :pass : :fail, detail: "streamed=#{streamed_statuses.tally} unstreamed=#{unstreamed_statuses.tally}" }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    ensure
      Raif.config.streaming_unsupported_model_keys = previous_unsupported
    end

    def self.classify_tool_call(model_completion)
      tool_call = model_completion&.response_tool_calls&.first
      return :no_tool_call if tool_call.nil?

      tool_call["arguments"].is_a?(Hash) ? :ok : :malformed
    end
    private_class_method :classify_tool_call

    def self.check_batch_inference(entry, batch_timeout:)
      llm = Raif.llm(entry.key)
      batch = llm.create_batch

      2.times do |i|
        llm.build_pending_model_completion(
          messages: [{ "role" => "user", "content" => COMPLETION_PROMPT }],
          raif_model_completion_batch: batch,
          batch_custom_id: "smoke-#{i}"
        )
      end

      llm.submit_batch!(batch)

      deadline = Time.now + batch_timeout
      loop do
        status = llm.fetch_batch_status!(batch)
        break if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(status.to_s)
        return { status: :timeout, detail: "still #{status} after #{batch_timeout}s" } if Time.now > deadline

        sleep 15
      end

      llm.fetch_batch_results!(batch)
      completions = batch.raif_model_completions.reload
      ok = completions.any? && completions.all? { |mc| response_text(mc).downcase.include?("ok") }
      { status: ok ? :pass : :fail, detail: "batch #{batch.status}" }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.check_images(entry)
      model_completion = Raif.llm(entry.key).chat(
        messages: [{
          role: "user",
          content: ["What text appears in this image? Reply with only that text.", Raif::ModelImageInput.new(input: IMAGE_FIXTURE)]
        }]
      )
      text = response_text(model_completion)
      { status: text.include?(NONCE) ? :pass : :fail, detail: text.first(180) }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.check_pdfs(entry)
      model_completion = Raif.llm(entry.key).chat(
        messages: [{
          role: "user",
          content: ["What text appears in this document? Reply with only that text.", Raif::ModelFileInput.new(input: PDF_FIXTURE)]
        }]
      )
      text = response_text(model_completion)
      { status: text.include?(NONCE) ? :pass : :fail, detail: text.first(180) }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.check_provider_managed_tools(entry, only_list:)
      llm = Raif.llm(entry.key)
      tool_names = Array(entry.capabilities["provider_managed_tools"])

      per_tool = tool_names.to_h { |tool_name| [tool_name, check_provider_managed_tool(llm, tool_name, only_list: only_list)] }

      { status: aggregate_status(per_tool.values.map { |result| result[:status] }),
        detail: per_tool.map { |name, result| "#{name}=#{result[:status]}" }.join(", ").first(180) }
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end

    def self.check_provider_managed_tool(llm, tool_name, only_list:)
      case tool_name.to_s
      when "web_search"
        model_completion = llm.chat(
          message: "Search the web for the current year and reply with it.",
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )
        { status: model_completion ? :pass : :fail, detail: response_text(model_completion).first(120) }
      when "code_execution"
        model_completion = llm.chat(
          message: "Use code execution to compute 7 * 6 and reply with the result.",
          available_model_tools: [Raif::ModelTools::ProviderManaged::CodeExecution]
        )
        text = response_text(model_completion)
        { status: text.include?("42") ? :pass : :fail, detail: text.first(120) }
      when "image_generation"
        if only_list == ["provider_managed_tools"]
          model_completion = llm.chat(
            message: "Generate a simple image of a red circle.",
            available_model_tools: [Raif::ModelTools::ProviderManaged::ImageGeneration]
          )
          { status: model_completion ? :pass : :fail, detail: response_text(model_completion).first(120) }
        else
          { status: :skip, detail: "not smoked (expensive)" }
        end
      else
        { status: :skip, detail: "no smoke check implemented for #{tool_name}" }
      end
    rescue StandardError => e
      { status: :fail, detail: "#{e.class}: #{e.message.to_s.first(180)}" }
    end
    private_class_method :check_provider_managed_tool

    def self.aggregate_status(statuses)
      return :pass if statuses.empty?
      return :fail if statuses.include?(:fail)
      return :timeout if statuses.include?(:timeout)
      return :skip if statuses.all? { |status| status == :skip }

      :pass
    end
    private_class_method :aggregate_status

    # Rebuilds entry's llm with `setting` force-enabled in model_provider_settings, then yields
    # it to the block. Used for the claimed-false direction of temperature/structured_outputs:
    # if the forced request still fails, that's the manifest's claim confirmed (status: :pass);
    # if it succeeds, the block reports the surprising result (status: :note).
    def self.probe_claimed_false_direction(entry, setting)
      config = Raif.llm_config(entry.key)
      forced = config[:llm_class].new(
        **config.except(:llm_class).merge(
          model_provider_settings: (config[:model_provider_settings] || {}).merge(setting => true)
        )
      )

      yield forced
    rescue StandardError => e
      { status: :pass, detail: "claim confirmed: #{e.class}: #{e.message.to_s.first(140)}" }
    end
    private_class_method :probe_claimed_false_direction

    def self.response_text(model_completion)
      model_completion.nil? ? "" : model_completion.raw_response.to_s
    end
    private_class_method :response_text

    def self.smoke_test_user
      Raif::TestUser.new(email: "smoke@example.invalid")
    end
    private_class_method :smoke_test_user
  end
end
