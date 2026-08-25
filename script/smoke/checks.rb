# frozen_string_literal: true

require "json"

# Runs the smoke capability checks for a single Raif::ModelManifest::Entry against its live
# Raif::Llm adapter. Requires Raif (and the dummy/host Rails app) already booted -- like
# Smoke::Credentials, this only references Raif.llm / Raif.llm_config / ActiveRecord models
# inside method bodies, so the file itself loads standalone.
#
# Every check rescues StandardError to a uniform { status: :fail, detail: "Class: message" }
# result (see fail_result/fail_detail; enriched with the provider's own error message when the
# exception carries an HTTP body): a live API call can fail in ways specific to each provider
# (timeouts, auth errors, malformed payloads), and the caller (bin/smoke) just needs a
# status/detail pair to report, not a raised exception to rescue itself. The claimed-false
# direction of a cheap probe (temperature, structured_outputs) additionally classifies some
# failures as :consistent -- see classify_claimed_false_error.
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

    WEB_SEARCH_PROMPT = "You must use the web_search tool right now to search the web for the current year. Do not answer " \
      "from memory or prior knowledge, even if you believe you already know it -- you must actually perform a live web " \
      "search and base your reply on its results."

    # Narrow, provider-agnostic signatures for "the provider rejected this claimed-false
    # capability's forced parameter with an error that specifically names it as unsupported" --
    # as opposed to any other 4xx (a malformed request, an unrelated validation error, a rate
    # limit) that says nothing about whether the manifest's claim is accurate. Keyed by the smoke
    # capability name (matching check_temperature/check_structured_outputs' own `claimed:`
    # dispatch), each entry is a small list of provider-shaped matchers rather than one generic
    # "unsupported" regex, since a generic regex would also match unrelated validation errors.
    # Each matcher receives the *parsed* JSON error body and returns true/false.
    #
    # Only ever reached for Faraday-backed providers (Anthropic, OpenAI, x.ai, OpenRouter,
    # Google): Bedrock's adapter raises Aws::BedrockRuntime::Client service errors, not
    # Faraday::ClientError, so a claimed-false Bedrock capability can never be classified here
    # and always stays :fail -- a correct but structurally invisible limitation.
    #
    # Scoped to these two probes only: run_check dispatches every other claimed-false-eligible
    # capability (native_tool_use, streaming, images, pdfs, batch_inference, provider_managed_tools)
    # without a `claimed:` argument at all, so even when one is explicitly forced to run via
    # --only despite being claimed false, a failure there is always a plain :fail, never
    # :consistent -- by design, since none of them reject via one single named parameter the way
    # temperature/response_format do.
    CLAIMED_FALSE_REJECTION_SIGNATURES = {
      "temperature" => [
        # Anthropic: {"type"=>"error","error"=>{"type"=>"invalid_request_error","message"=>"...temperature...deprecated..."}}.
        # Production Anthropic rejection body as of 2026-08-25: temperature:false models reject
        # with exactly "`temperature` is deprecated for this model." Earlier extended-thinking
        # phrasings ("may only be set to 1 when thinking is enabled", "Extra inputs are not
        # permitted") are kept in the alternation since older API versions still emit them.
        lambda do |parsed|
          message = anthropic_invalid_request_message(parsed)
          message&.match?(/temperature/i) &&
            message.match?(/not support|unsupported|may not be set|may only be set|not permitted|deprecated/i)
        end,
        # OpenAI-shaped (OpenAI, x.ai, OpenRouter): {"error"=>{"message"=>"...","param"=>"temperature","code"=>"unsupported_parameter"}}
        lambda do |parsed|
          error = openai_unsupported_parameter_error(parsed)
          error && (error["param"].to_s.match?(/temperature/i) || error["message"].to_s.match?(/temperature/i))
        end
      ],
      "structured_outputs" => [
        lambda do |parsed|
          message = anthropic_invalid_request_message(parsed)
          message&.match?(/response_format|json_schema|structured output/i) && message.match?(/not support|unsupported|may not be set/i)
        end,
        lambda do |parsed|
          error = openai_unsupported_parameter_error(parsed)
          error && (error["param"].to_s.match?(/response_format/i) || error["message"].to_s.match?(/response_format|json_schema/i))
        end
      ]
    }.freeze

    STRUCTURED_OUTPUTS_PROMPT = "Tell me a joke. Reply with a JSON object that has a 'joke' key " \
      "and an 'answer' key. Both values must be non-empty strings."
    STRUCTURED_OUTPUTS_REQUIRED_KEYS = %w[joke answer].freeze

    # AR-backed source for the structured_outputs check. Polymorphic `belongs_to :source` on
    # Raif::ModelCompletion needs a real ActiveRecord class; a Raif::Task subclass with a
    # small fixed schema (joke + answer) is sufficient to verify JSON enforcement end-to-end
    # without being domain-specific.
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

        observed_result = run_check(
          entry, capability, claimed: claimed, iterations: iterations, batch_timeout: batch_timeout, only_list: only_list
        )
        results[capability] = verdict_for(claimed: claimed, observed_result: observed_result)
      end

      results
    end

    # Converts a raw check result into a claim-aware verdict. A claimed-false capability that
    # passes is downgraded to :note rather than :pass: whether the check ran because it's cheap
    # enough to probe anyway (temperature, structured_outputs) or because it was explicitly
    # requested via --only despite being claimed-false and expensive, a passing result there
    # means the manifest's claim is wrong, not that the capability is verified as claimed.
    # Every other result (claimed true, or not a :pass) passes through unchanged.
    def self.verdict_for(claimed:, observed_result:)
      return observed_result if claimed
      return observed_result unless observed_result[:status] == :pass

      observed_result.merge(
        status: :note,
        detail: "claimed unsupported but appears to work: #{observed_result[:detail]}"
      )
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
      { status: exact_ok?(text) ? :pass : :fail, detail: text.first(180) }
    rescue StandardError => e
      fail_result(e)
    end

    # The rescue routes to classify_claimed_false_error only in the claimed-false direction: a
    # claimed-true failure is always a plain :fail, never eligible for :consistent, since
    # :consistent specifically means "the provider rejected this as the manifest's claimed-false
    # entry said it would" -- a claim that doesn't exist on the claimed-true path.
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
      claimed ? fail_result(e) : classify_claimed_false_error("temperature", e)
    end

    def self.check_structured_outputs(entry, claimed:)
      if claimed
        run_structured_outputs_probe(Raif.llm(entry.key))
      else
        probe_claimed_false_direction(entry, :supports_structured_outputs) { |llm| run_structured_outputs_probe(llm) }
      end
    rescue StandardError => e
      claimed ? fail_result(e) : classify_claimed_false_error("structured_outputs", e)
    end

    # A pass here is not automatically recordable evidence of native structured-output support:
    # the JSON-tool fallback (prompting for JSON and parsing the reply) can produce a valid
    # object even on a model with no native response_format support at all, so that path is
    # tagged recordable: false. Only a pass with response_format_parameter.present? -- meaning
    # the provider actually enforced the schema -- is recordable. The claimed-false direction's
    # own :note downgrade is handled by the caller's verdict_for, not here, so both the native
    # and fallback pass paths get the same claim-aware treatment.
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
        result = { status: :pass, detail: native ? "native" : "json_response_tool" }
        native ? result : result.merge(recordable: false)
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
      fail_result(e)
    end

    # streaming_unsupported_model_keys is cleared once for the whole process in script/smoke.rb;
    # do not save/restore it here too (see the comment there for why).
    def self.check_streaming(entry)
      llm = Raif.llm(entry.key)
      deltas = 0
      streamed = llm.chat(message: COMPLETION_PROMPT) { |_model_completion, _delta, _event| deltas += 1 }
      unstreamed = llm.chat(message: COMPLETION_PROMPT)

      streamed_ok = exact_ok?(response_text(streamed))
      unstreamed_ok = exact_ok?(response_text(unstreamed))
      pass = streamed_ok && unstreamed_ok && deltas > 0

      { status: pass ? :pass : :fail, detail: "deltas=#{deltas} streamed_ok=#{streamed_ok} unstreamed_ok=#{unstreamed_ok}" }
    rescue StandardError => e
      fail_result(e)
    end

    def self.check_streaming_tool_calls(entry, iterations:)
      return { status: :fail, detail: "iterations must be >= 1" } unless iterations >= 1

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

      pass = streamed_statuses.all? { |status| status == :ok } && unstreamed_statuses.all? { |status| status == :ok }
      { status: pass ? :pass : :fail, detail: "streamed=#{streamed_statuses.tally} unstreamed=#{unstreamed_statuses.tally}" }
    rescue StandardError => e
      fail_result(e)
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

      expected_custom_ids = Array.new(2) { |i| "smoke-#{i}" }
      expected_custom_ids.each do |custom_id|
        llm.build_pending_model_completion(
          messages: [{ "role" => "user", "content" => COMPLETION_PROMPT }],
          raif_model_completion_batch: batch,
          batch_custom_id: custom_id
        )
      end

      llm.submit_batch!(batch)

      deadline = Time.now + batch_timeout
      status = nil
      loop do
        status = llm.fetch_batch_status!(batch).to_s
        break if Raif::ModelCompletionBatch::TERMINAL_STATUSES.include?(status)
        return { status: :timeout, detail: "still #{status} after #{batch_timeout}s" } if Time.now > deadline

        sleep 15
      end

      return { status: :fail, detail: "batch ended with non-success status: #{status}" } unless status == "ended"

      llm.fetch_batch_results!(batch)
      completions = batch.raif_model_completions.reload
      present_custom_ids = completions.map(&:batch_custom_id)
      missing_custom_ids = expected_custom_ids - present_custom_ids
      results_ok = completions.any? && completions.all? { |mc| exact_ok?(response_text(mc)) }

      if missing_custom_ids.empty? && results_ok
        { status: :pass, detail: "batch #{status}" }
      else
        { status: :fail, detail: "batch #{status} missing_custom_ids=#{missing_custom_ids.inspect}" }
      end
    rescue StandardError => e
      fail_result(e)
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
      fail_result(e)
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
      fail_result(e)
    end

    def self.check_provider_managed_tools(entry, only_list:)
      llm = Raif.llm(entry.key)
      tool_names = Array(entry.capabilities[:provider_managed_tools])

      per_tool = tool_names.to_h { |tool_name| [tool_name, check_provider_managed_tool(llm, tool_name, only_list: only_list)] }

      # Not truncated to the usual 180-char convention: each per-tool piece is already bounded
      # and well-formed on its own (see truncate_response_text), so a further blind cut here
      # could land mid-structure and reintroduce the unbalanced-looking output this format fixes.
      { status: aggregate_status(per_tool.values.map { |result| result[:status] }),
        detail: provider_managed_tools_detail(per_tool) }
    rescue StandardError => e
      fail_result(e)
    end

    STATUS_DETAIL_LABELS = {
      pass: "pass",
      fail: "failed",
      timeout: "timed out",
      skip: "skipped"
    }.freeze

    # Groups per-tool results by status, in order of first appearance (so a pass-then-skip run
    # reads "pass: ...; skipped: ..." rather than being reordered by severity). Only non-pass
    # entries carry their per-tool detail, since that's the part worth surfacing.
    def self.provider_managed_tools_detail(per_tool)
      per_tool.values.map { |result| result[:status] }.uniq.map do |status|
        names = per_tool.filter_map do |name, result|
          next unless result[:status] == status

          status == :pass ? name.to_s : "#{name} (#{result[:detail]})"
        end

        "#{STATUS_DETAIL_LABELS.fetch(status, status.to_s)}: #{names.join(", ")}"
      end.join("; ")
    end
    private_class_method :provider_managed_tools_detail

    def self.check_provider_managed_tool(llm, tool_name, only_list:)
      case tool_name.to_s
      when "web_search"
        model_completion = llm.chat(
          message: WEB_SEARCH_PROMPT,
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )
        provider_managed_tool_result(model_completion, "web_search")
      when "code_execution"
        model_completion = llm.chat(
          message: "Use code execution to compute 7 * 6 and reply with the result.",
          available_model_tools: [Raif::ModelTools::ProviderManaged::CodeExecution]
        )
        provider_managed_tool_result(model_completion, "code_execution")
      when "image_generation"
        if only_list&.include?("provider_managed_tools")
          model_completion = llm.chat(
            message: "Generate a simple image of a red circle.",
            available_model_tools: [Raif::ModelTools::ProviderManaged::ImageGeneration]
          )
          provider_managed_tool_result(model_completion, "image_generation")
        else
          { status: :skip, detail: "expensive; run --only provider_managed_tools" }
        end
      else
        { status: :skip, detail: "no smoke check implemented for #{tool_name}" }
      end
    rescue StandardError => e
      fail_result(e)
    end
    private_class_method :check_provider_managed_tool

    # Neither a non-nil completion object nor text that happens to mention the expected answer
    # (e.g. "42" for a code-execution arithmetic prompt) is evidence the provider actually
    # invoked the tool -- the model can produce that text from its own knowledge. The only real
    # evidence is a Raif::ModelCompletion#provider_managed_tool_calls entry naming this tool.
    #
    # A failing detail is labeled and cleanly truncated rather than embedding the model's raw
    # response text as-is: a plain `text.first(120)` can cut mid-word, and once that fragment
    # sits inside provider_managed_tools_detail's enclosing "name (...)" grouping it reads as
    # garbage (e.g. "web_search (... I didn't need to perfor)").
    def self.provider_managed_tool_result(model_completion, tool_name)
      matched = Array(model_completion&.provider_managed_tool_calls).any? { |call| call["tool_name"] == tool_name }
      return { status: :pass, detail: response_text(model_completion).first(120) } if matched

      { status: :fail, detail: "no matching provider tool call; response_text: \"#{truncate_response_text(model_completion)}\"" }
    end
    private_class_method :provider_managed_tool_result

    RESPONSE_TEXT_PREVIEW_LENGTH = 120

    # Truncates at the last whole word within RESPONSE_TEXT_PREVIEW_LENGTH chars, with a trailing
    # ellipsis, so a preview never ends mid-word -- unlike String#first(N), which cuts wherever
    # the Nth character happens to fall. Returned unchanged (no ellipsis) when already short.
    def self.truncate_response_text(model_completion)
      text = response_text(model_completion).strip
      return text if text.length <= RESPONSE_TEXT_PREVIEW_LENGTH

      truncated = text[0, RESPONSE_TEXT_PREVIEW_LENGTH]
      word_boundary = truncated.rindex(" ")
      truncated = truncated[0, word_boundary] if word_boundary

      "#{truncated}..."
    end
    private_class_method :truncate_response_text

    # fail > timeout > skip > pass: any skipped tool (e.g. one omitted from this run as
    # expensive) keeps the whole capability out of :pass, so an unverified tool can't hide
    # inside a passing aggregate.
    def self.aggregate_status(statuses)
      return :pass if statuses.empty?
      return :fail if statuses.include?(:fail)
      return :timeout if statuses.include?(:timeout)
      return :skip if statuses.include?(:skip)

      :pass
    end
    private_class_method :aggregate_status

    # Rebuilds entry's llm with `setting` force-enabled in model_provider_settings, then yields
    # it to the block. Used for the claimed-false direction of temperature/structured_outputs.
    # The block reports :pass when the forced request succeeds; run_for's verdict_for then
    # downgrades that to :note, since a claimed-false capability that works means the manifest's
    # claim is wrong. Any exception here (auth failure, timeout, typo) is left to propagate to
    # the caller's own rescue, which classifies it (see classify_claimed_false_error) but never
    # as a :pass -- an exception is not evidence the claim is true.
    def self.probe_claimed_false_direction(entry, setting)
      config = Raif.llm_config(entry.key)
      forced = config[:llm_class].new(
        **config.except(:llm_class).merge(
          model_provider_settings: (config[:model_provider_settings] || {}).merge(setting => true)
        )
      )

      yield forced
    end
    private_class_method :probe_claimed_false_direction

    # Classifies an exception raised during the claimed-false direction of a cheap probe
    # (temperature, structured_outputs) as :consistent -- the provider rejected the forced
    # parameter with an error that specifically names it as unsupported, matching the manifest's
    # claim -- or otherwise :fail, same as an unclassified error. Only an HTTP 4xx client error
    # is eligible: 5xx, timeouts, connection failures, and auth failures (401/403) are excluded
    # by status alone, before content is even considered, since none of them says anything about
    # whether the claim is accurate. Exclusion is by status/type, not by absence of a content
    # match, so an auth failure or timeout can never be misread as "claim confirmed."
    def self.classify_claimed_false_error(probe, exception)
      return fail_result(exception) unless exception.is_a?(Faraday::ClientError)

      status = exception.response_status
      return fail_result(exception) unless status && status >= 400 && status < 500 && ![401, 403].include?(status)

      parsed = parse_error_body(exception.response_body)
      matchers = CLAIMED_FALSE_REJECTION_SIGNATURES[probe] || []
      return fail_result(exception) unless parsed && matchers.any? { |matcher| matcher.call(parsed) }

      api_message = extract_api_error_message(parsed)
      { status: :consistent, detail: "rejected by provider as declared: #{api_message}".first(180) }
    end
    private_class_method :classify_claimed_false_error

    def self.fail_result(exception)
      { status: :fail, detail: fail_detail(exception) }
    end
    private_class_method :fail_result

    # The plain "Class: message" detail every check produces on failure, enriched with the
    # provider's own error message when the exception is an HTTP error whose body carries one --
    # e.g. "Faraday::BadRequestError: 400 temperature is not supported for this model" instead of
    # Faraday::Error#message's uninformative "the server responded with status 400 for POST ...",
    # so a FAIL is debuggable straight from the matrix without re-running with --record or digging
    # through logs.
    def self.fail_detail(exception)
      plain = "#{exception.class}: #{exception.message}"
      return plain.first(180) unless exception.is_a?(Faraday::Error)

      parsed = parse_error_body(exception.response_body)
      api_message = parsed && extract_api_error_message(parsed)
      return plain.first(180) if api_message.blank?

      "#{exception.class}: #{exception.response_status} #{api_message}".first(180)
    end
    private_class_method :fail_detail

    def self.parse_error_body(body)
      return nil if body.blank?
      # Faraday's :json response middleware can also run before :raise_error (adapter-ordering
      # dependent), leaving response_body already parsed into a Hash -- JSON.parse would raise
      # TypeError on that, not JSON::ParserError, so it's handled explicitly rather than by rescue.
      return body if body.is_a?(Hash)

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parse_error_body

    # Anthropic-shaped: {"type"=>"error","error"=>{"type"=>"...","message"=>"..."}}.
    # OpenAI-shaped (OpenAI, x.ai, OpenRouter): {"error"=>{"message"=>"...","type"=>...,"param"=>...,"code"=>...}}.
    # Both put the human-readable reason at error.message, so one extractor covers both shapes.
    def self.extract_api_error_message(parsed)
      return nil unless parsed.is_a?(Hash)

      error = parsed["error"]
      return nil unless error.is_a?(Hash)

      error["message"]
    end
    private_class_method :extract_api_error_message

    def self.anthropic_invalid_request_message(parsed)
      return nil unless parsed.is_a?(Hash) && parsed["type"] == "error"

      error = parsed["error"]
      return nil unless error.is_a?(Hash) && error["type"] == "invalid_request_error"

      error["message"].to_s
    end
    private_class_method :anthropic_invalid_request_message

    def self.openai_unsupported_parameter_error(parsed)
      return nil unless parsed.is_a?(Hash)

      error = parsed["error"]
      return nil unless error.is_a?(Hash) && %w[unsupported_parameter unsupported_value].include?(error["code"])

      error
    end
    private_class_method :openai_unsupported_parameter_error

    def self.response_text(model_completion)
      model_completion.nil? ? "" : model_completion.raw_response.to_s
    end
    private_class_method :response_text

    # A response merely containing "ok" (e.g. "not okay", "okay, sure") is not evidence the
    # model followed COMPLETION_PROMPT's exact instruction; only an exact case-insensitive match
    # on the trimmed text counts.
    def self.exact_ok?(text)
      text.to_s.strip.casecmp("ok").zero?
    end
    private_class_method :exact_ok?

    def self.smoke_test_user
      Raif::TestUser.new(email: "smoke@example.invalid")
    end
    private_class_method :smoke_test_user
  end
end
