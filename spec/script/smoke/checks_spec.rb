# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"
require Raif::Engine.root.join("script/smoke/checks")
require Raif::Engine.root.join("script/smoke/observation_recorder")
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Smoke::Checks do
  # A fixture entry with a deliberate mix of claims, so a single run_for call can exercise every
  # dispatch rule: temperature/structured_outputs are claimed false but cheap (probed anyway);
  # batch_inference/images are claimed false and expensive (omitted unless explicitly requested);
  # native_tool_use/streaming/pdfs/provider_managed_tools are claimed true (run normally); and
  # streaming + native_tool_use both being true derives the streaming_tool_calls capability.
  let(:entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_test_model,
      provider_name: :anthropic,
      endpoint: nil,
      adapter_class_name: "Raif::Llms::Anthropic",
      api_name: "smoke-checks-test-1",
      display_name: "Smoke Checks Test Model",
      max_completion_tokens: 4096,
      pricing: { input_per_million: 1.0, output_per_million: 2.0 },
      capabilities: {
        temperature: false,
        structured_outputs: false,
        native_tool_use: true,
        streaming: true,
        batch_inference: false,
        images: false,
        pdfs: true,
        provider_managed_tools: %i[web_search]
      },
      lifecycle: { status: :active },
      source_path: "spec/fixtures/model_manifest/anthropic.rb",
      key_base: "smoke_checks_test_model"
    )
  end

  # native_tool_use claimed true but streaming claimed false (e.g. a model whose streaming
  # path is disabled/broken): streaming_tool_calls is smokable but claimed false, so a full
  # run should omit it while --only streaming_tool_calls still runs it as a diagnostic.
  let(:streaming_disabled_entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_streaming_disabled_test_model,
      provider_name: :anthropic,
      endpoint: nil,
      adapter_class_name: "Raif::Llms::Anthropic",
      api_name: "smoke-checks-streaming-disabled-test-1",
      display_name: "Smoke Checks Streaming Disabled Test Model",
      max_completion_tokens: 4096,
      pricing: { input_per_million: 1.0, output_per_million: 2.0 },
      capabilities: {
        temperature: false,
        structured_outputs: false,
        native_tool_use: true,
        streaming: false,
        batch_inference: false,
        images: false,
        pdfs: true,
        provider_managed_tools: %i[web_search]
      },
      lifecycle: { status: :active },
      source_path: "spec/fixtures/model_manifest/anthropic.rb",
      key_base: "smoke_checks_streaming_disabled_test_model"
    )
  end

  # Claimed false for every schema capability, used by the claimed-false verdict matrix: cheap
  # probes (temperature, structured_outputs) probe anyway, and expensive checks (native_tool_use,
  # streaming, batch_inference, images, pdfs) only run when explicitly requested via --only. In
  # both cases a success should be reported as :note, not :pass.
  let(:claimed_false_entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_claimed_false_test_model,
      provider_name: :anthropic,
      endpoint: nil,
      adapter_class_name: "Raif::Llms::Anthropic",
      api_name: "smoke-checks-claimed-false-test-1",
      display_name: "Smoke Checks Claimed False Test Model",
      max_completion_tokens: 4096,
      pricing: { input_per_million: 1.0, output_per_million: 2.0 },
      capabilities: {
        temperature: false,
        structured_outputs: false,
        native_tool_use: false,
        streaming: false,
        batch_inference: false,
        images: false,
        pdfs: false
      },
      lifecycle: { status: :active },
      source_path: "spec/fixtures/model_manifest/anthropic.rb",
      key_base: "smoke_checks_claimed_false_test_model"
    )
  end

  # Minimal entry for exercising check_provider_managed_tools directly: that method only calls
  # Raif.llm(entry.key) and reads entry.capabilities[:provider_managed_tools], so the rest of
  # the Entry fields are irrelevant here.
  let(:pmt_entry) do
    Raif::ModelManifest::Entry.new(
      key: :smoke_checks_pmt_test_model,
      capabilities: { provider_managed_tools: %i[web_search image_generation] }
    )
  end

  # provider_managed_tool_calls defaults to matching evidence for all three provider-managed
  # tools this suite exercises (web_search, code_execution, image_generation), so tests that
  # don't care about provider-managed tool evidence (most of them) keep seeing a pass without
  # each needing its own stub; tests that DO care override it per-example.
  let(:model_completion) do
    instance_double(
      Raif::ModelCompletion,
      raw_response: "ok",
      response_tool_calls: [{ "name" => "wikipedia_search", "arguments" => { "query" => "PM of Canada" } }],
      response_format_parameter: "json_schema",
      provider_managed_tool_calls: [
        { "tool_name" => "web_search", "provider_tool_call_id" => "search_1" },
        { "tool_name" => "code_execution", "provider_tool_call_id" => "code_1" },
        { "tool_name" => "image_generation", "provider_tool_call_id" => "image_1" }
      ]
    )
  end

  let(:batch_relation) { double("raif_model_completions relation", reload: []) }

  let(:batch) do
    instance_double(Raif::ModelCompletionBatch, status: "ended", raif_model_completions: batch_relation)
  end

  let(:llm) do
    instance_double(
      Raif::Llms::Anthropic,
      chat: model_completion,
      create_batch: batch,
      build_pending_model_completion: instance_double(Raif::ModelCompletion),
      submit_batch!: batch,
      fetch_batch_status!: "ended",
      fetch_batch_results!: batch
    )
  end

  # The claimed-false direction of temperature/structured_outputs rebuilds the llm via
  # Raif.llm_config(entry.key)[:llm_class].new(...) rather than going through Raif.llm, so it
  # needs its own stub -- a lightweight class that accepts the forced model_provider_settings
  # kwargs and never makes a real request. The raw_response is valid JSON matching the
  # structured_outputs schema (joke/answer) so both check_temperature (which ignores the chat
  # return value) and check_structured_outputs (which parses it) see a successful probe.
  let(:forced_llm_class) do
    Class.new do
      def initialize(**_kwargs); end

      def chat(**_kwargs)
        raw_response = { joke: "Why did the chicken cross the road?", answer: "To get to the other side" }.to_json
        Struct.new(:raw_response, :response_format_parameter, :response_tool_calls).new(raw_response, "json_schema", nil)
      end
    end
  end

  before do
    allow(Raif).to receive(:llm).with(entry.key).and_return(llm)
    allow(Raif).to receive(:llm_config).with(entry.key).and_return(llm_class: forced_llm_class, model_provider_settings: {})
    allow(Raif).to receive(:llm).with(streaming_disabled_entry.key).and_return(llm)
    allow(Raif).to receive(:llm_config).with(streaming_disabled_entry.key).and_return(
      llm_class: forced_llm_class, model_provider_settings: {}
    )
    allow(Raif).to receive(:llm).with(claimed_false_entry.key).and_return(llm)
    allow(Raif).to receive(:llm_config).with(claimed_false_entry.key).and_return(
      llm_class: forced_llm_class, model_provider_settings: {}
    )
    allow(Raif).to receive(:llm).with(pmt_entry.key).and_return(llm)
  end

  # Runs .run_for restricted to a single capability and unwraps that capability's result, for
  # tests that only care about one check's hard-oracle behavior.
  def check_result_for(capability, target_entry: entry)
    described_class.run_for(target_entry, only: capability).fetch(capability)
  end

  describe "NONCE" do
    it "is the fixed marker text embedded in the image/pdf fixtures" do
      expect(described_class::NONCE).to eq("RAIF-SMOKE-7391")
    end
  end

  describe ".run_for" do
    it "runs every smokable capability, probing claimed-false cheap ones but omitting claimed-false expensive ones" do
      result = described_class.run_for(entry)

      expect(result.keys).to contain_exactly(
        "completion", "temperature", "structured_outputs", "native_tool_use",
        "streaming", "streaming_tool_calls", "pdfs", "provider_managed_tools"
      )
    end

    it "probes claimed-false cheap capabilities (temperature, structured_outputs) rather than omitting them" do
      result = described_class.run_for(entry)

      expect(result).to have_key("temperature")
      expect(result).to have_key("structured_outputs")
    end

    it "omits claimed-false expensive capabilities (batch_inference, images) from the result entirely" do
      result = described_class.run_for(entry)

      expect(result).not_to have_key("batch_inference")
      expect(result).not_to have_key("images")
    end

    it "restricts the run to just the capability named by only" do
      result = described_class.run_for(entry, only: "streaming")

      expect(result.keys).to eq(["streaming"])
    end

    it "restricts the run to an array of capabilities named by only" do
      result = described_class.run_for(entry, only: ["completion", "pdfs"])

      expect(result.keys).to contain_exactly("completion", "pdfs")
    end

    it "reports a skipped capability as status: :skip instead of running it" do
      result = described_class.run_for(entry, skip: ["pdfs"])

      expect(result["pdfs"]).to eq(status: :skip, detail: "skipped via --skip")
    end

    it "still runs every other capability when one is skipped" do
      result = described_class.run_for(entry, skip: ["pdfs"])

      expect(result).to have_key("completion")
      expect(result).to have_key("temperature")
    end

    it "forces a claimed-false expensive capability to run when explicitly requested via only" do
      result = described_class.run_for(entry, only: ["batch_inference"])

      expect(result.keys).to eq(["batch_inference"])
    end

    it "does not run a check for a capability the entry doesn't claim to have (only filters before dispatch)" do
      result = described_class.run_for(entry, only: ["not_a_real_capability"])

      expect(result).to be_empty
    end

    it "omits claimed-false streaming_tool_calls (native_tool_use true, streaming false) from a full run" do
      result = described_class.run_for(streaming_disabled_entry)

      expect(result).not_to have_key("streaming_tool_calls")
    end

    it "runs streaming_tool_calls when explicitly requested via only, despite streaming being claimed false" do
      result = described_class.run_for(streaming_disabled_entry, only: "streaming_tool_calls")

      expect(result.keys).to eq(["streaming_tool_calls"])
    end
  end

  # The claimed-false verdict matrix:
  #   1. a cheap claimed-false probe (temperature, structured_outputs) that succeeds: :note,
  #      not :pass.
  #   2. an exception during a claimed-false probe: :fail, never a "claim confirmed" :pass --
  #      an auth failure or timeout is not evidence the claim is true.
  #   3. an expensive check (native_tool_use, streaming, streaming_tool_calls, batch_inference,
  #      images, pdfs) explicitly requested via --only despite being claimed false, that
  #      succeeds: :note, not :pass -- --only doesn't make the claim true.
  describe "claimed-false verdicts" do
    # Case 1.
    it "reports a working claimed-false temperature probe as :note" do
      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 1.
    it "reports a working claimed-false structured_outputs probe as :note" do
      result = described_class.run_for(claimed_false_entry, only: "structured_outputs")

      expect(result.fetch("structured_outputs")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 2. Rebuilds the forced llm as a class whose chat always raises, the same shape as
    # forced_llm_class but for the failure direction.
    it "reports an exception during a claimed-false temperature probe as :fail" do
      raising_llm_class = Class.new do
        def initialize(**_kwargs); end
        def chat(**_kwargs) = raise(Faraday::UnauthorizedError, "401")
      end
      allow(Raif).to receive(:llm_config).with(claimed_false_entry.key).and_return(
        llm_class: raising_llm_class, model_provider_settings: {}
      )

      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to include(status: :fail)
      expect(result.fetch("temperature").fetch(:detail)).not_to include("claim confirmed")
    end

    # Case 2.
    it "reports an exception during a claimed-false structured_outputs probe as :fail" do
      raising_llm_class = Class.new do
        def initialize(**_kwargs); end
        def chat(**_kwargs) = raise(Faraday::UnauthorizedError, "401")
      end
      allow(Raif).to receive(:llm_config).with(claimed_false_entry.key).and_return(
        llm_class: raising_llm_class, model_provider_settings: {}
      )

      result = described_class.run_for(claimed_false_entry, only: "structured_outputs")

      expect(result.fetch("structured_outputs")).to include(status: :fail)
      expect(result.fetch("structured_outputs").fetch(:detail)).not_to include("claim confirmed")
    end

    # Not routed through probe_claimed_false_direction like the cases above -- check_streaming's
    # own rescue already returns :fail regardless of the claim -- but it guards the same
    # "exceptions never confirm a claim" principle.
    it "reports an exception during a claimed-false streaming check as :fail" do
      allow(llm).to receive(:chat).and_raise(Faraday::UnauthorizedError.new("401"))

      result = described_class.run_for(claimed_false_entry, only: "streaming")

      expect(result.fetch("streaming")).to include(status: :fail)
      expect(result.fetch("streaming").fetch(:detail)).not_to include("claim confirmed")
    end

    # Case 3: native_tool_use claimed false, explicitly requested; the default llm/model_completion
    # stubs already represent a working tool call.
    it "reports a working explicitly requested claimed-false native_tool_use check as :note" do
      result = described_class.run_for(claimed_false_entry, only: "native_tool_use")

      expect(result.fetch("native_tool_use")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 3: streaming claimed false, explicitly requested. Needs its own chat stub that
    # actually yields to the block, since the default llm stub does not.
    it "reports a working explicitly requested claimed-false streaming check as :note" do
      allow(llm).to receive(:chat) do |**_kwargs, &block|
        block&.call(model_completion, "delta", :event)
        model_completion
      end

      result = described_class.run_for(claimed_false_entry, only: "streaming")

      expect(result.fetch("streaming")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 3: streaming_tool_calls claimed false (native_tool_use true, streaming false),
    # explicitly requested. Uses streaming_disabled_entry since claimed_false_entry's
    # native_tool_use: false keeps streaming_tool_calls out of smokable_capabilities entirely.
    it "reports a working explicitly requested claimed-false streaming_tool_calls check as :note" do
      result = described_class.run_for(streaming_disabled_entry, only: "streaming_tool_calls")

      expect(result.fetch("streaming_tool_calls")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 3: batch_inference claimed false, explicitly requested. Needs its own
    # batch_relation.reload stub, since the default one returns no completions; both expected
    # custom IDs must be present now that check_batch_inference verifies them.
    it "reports a working explicitly requested claimed-false batch_inference check as :note" do
      ok_completions = [
        instance_double(Raif::ModelCompletion, raw_response: "ok", batch_custom_id: "smoke-0"),
        instance_double(Raif::ModelCompletion, raw_response: "ok", batch_custom_id: "smoke-1")
      ]
      allow(batch_relation).to receive(:reload).and_return(ok_completions)

      result = described_class.run_for(claimed_false_entry, only: "batch_inference")

      expect(result.fetch("batch_inference")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 3: images claimed false, explicitly requested. Needs its own chat stub returning the
    # NONCE text, since the default model_completion's raw_response doesn't contain it.
    it "reports a working explicitly requested claimed-false images check as :note" do
      allow(llm).to receive(:chat).and_return(instance_double(Raif::ModelCompletion, raw_response: described_class::NONCE))

      result = described_class.run_for(claimed_false_entry, only: "images")

      expect(result.fetch("images")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end

    # Case 3: pdfs claimed false, explicitly requested. Same NONCE-bearing chat stub as the
    # images case above.
    it "reports a working explicitly requested claimed-false pdfs check as :note" do
      allow(llm).to receive(:chat).and_return(instance_double(Raif::ModelCompletion, raw_response: described_class::NONCE))

      result = described_class.run_for(claimed_false_entry, only: "pdfs")

      expect(result.fetch("pdfs")).to include(
        status: :note,
        detail: include("claimed unsupported but appears to work")
      )
    end
  end

  # :consistent means "the provider rejected this claimed-false capability's forced parameter
  # with an error that specifically names it as unsupported, matching the manifest's claim" --
  # as opposed to a bare :fail, which is any other 4xx/5xx/auth/non-HTTP failure that says
  # nothing about whether the claim is accurate. Classification only ever happens in the
  # claimed-false direction (verified by the "claimed-true" examples below), and only for a
  # narrow set of provider error shapes (verified by the "unmatched" examples).
  describe "claimed-false rejection classification (:consistent)" do
    def bad_request_error(body, status: 400)
      Faraday::BadRequestError.new({ status: status, body: body })
    end

    def anthropic_rejection_body(message)
      { type: "error", error: { type: "invalid_request_error", message: message } }.to_json
    end

    def openai_rejection_body(param:, code: "unsupported_parameter", message:)
      { error: { message: message, type: "invalid_request_error", param: param, code: code } }.to_json
    end

    def raising_llm_class_for(exception)
      Class.new do
        define_method(:initialize) { |**_kwargs| }
        define_method(:chat) { |**_kwargs| raise exception }
      end
    end

    def stub_forced_llm_raising(exception)
      allow(Raif).to receive(:llm_config).with(claimed_false_entry.key).and_return(
        llm_class: raising_llm_class_for(exception), model_provider_settings: {}
      )
    end

    it "classifies an Anthropic invalid_request_error naming temperature as unsupported as :consistent" do
      stub_forced_llm_raising(bad_request_error(anthropic_rejection_body("temperature is not supported for this model")))

      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to eq(
        status: :consistent,
        detail: "rejected by provider as declared: temperature is not supported for this model"
      )
    end

    # Production Anthropic rejection body as of 2026-08-25, from the temperature:false models
    # (claude_5_fable/5_sonnet/4_8_opus/4_7_opus).
    it "classifies the pinned production Anthropic wording ('is deprecated for this model') as :consistent" do
      stub_forced_llm_raising(bad_request_error(
        anthropic_rejection_body("`temperature` is deprecated for this model.")
      ))

      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to include(status: :consistent, detail: include("deprecated for this model"))
    end

    # Older extended-thinking phrasings, kept matched since older API versions still emit them.
    it "classifies the extended-thinking Anthropic wording ('may only be set') as :consistent" do
      stub_forced_llm_raising(bad_request_error(
        anthropic_rejection_body("`temperature` may only be set to 1 when thinking is enabled for this model")
      ))

      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to include(status: :consistent, detail: include("may only be set to 1"))
    end

    # The other extended-thinking phrasing for the same rejection.
    it "classifies the extended-thinking Anthropic wording ('Extra inputs are not permitted') as :consistent" do
      stub_forced_llm_raising(bad_request_error(
        anthropic_rejection_body("temperature: Extra inputs are not permitted when thinking is enabled")
      ))

      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to include(status: :consistent, detail: include("Extra inputs are not permitted"))
    end

    it "classifies an OpenAI unsupported_parameter error naming temperature as :consistent" do
      stub_forced_llm_raising(bad_request_error(openai_rejection_body(
        param: "temperature", message: "Unsupported value: 'temperature' is not supported with this model."
      )))

      result = described_class.run_for(claimed_false_entry, only: "temperature")

      expect(result.fetch("temperature")).to include(status: :consistent, detail: include("Unsupported value"))
    end

    it "classifies an Anthropic invalid_request_error naming response_format as unsupported structured_outputs as :consistent" do
      stub_forced_llm_raising(bad_request_error(anthropic_rejection_body("response_format is not supported for this model")))

      result = described_class.run_for(claimed_false_entry, only: "structured_outputs")

      expect(result.fetch("structured_outputs")).to include(status: :consistent, detail: include("response_format"))
    end

    it "classifies an OpenAI unsupported_parameter error naming response_format as :consistent for structured_outputs" do
      stub_forced_llm_raising(bad_request_error(openai_rejection_body(
        param: "response_format", message: "Unsupported parameter: 'response_format' is not supported with this model."
      )))

      result = described_class.run_for(claimed_false_entry, only: "structured_outputs")

      expect(result.fetch("structured_outputs")).to include(status: :consistent)
    end

    it "does not classify a bare 400 with an unrelated message (stays :fail)" do
      result = described_class.send(
        :classify_claimed_false_error, "temperature", bad_request_error(anthropic_rejection_body("max_tokens must be a positive integer"))
      )

      expect(result[:status]).to eq(:fail)
    end

    it "does not classify a 400 with an unparseable (non-JSON) body (stays :fail)" do
      result = described_class.send(:classify_claimed_false_error, "temperature", bad_request_error("not json at all"))

      expect(result[:status]).to eq(:fail)
    end

    it "does not classify a 5xx error, even with matching content (stays :fail)" do
      error = Faraday::ServerError.new({ status: 500, body: anthropic_rejection_body("temperature is not supported for this model") })

      result = described_class.send(:classify_claimed_false_error, "temperature", error)

      expect(result[:status]).to eq(:fail)
    end

    it "does not classify a 401 auth error, even with matching content (stays :fail)" do
      error = Faraday::UnauthorizedError.new({ status: 401, body: anthropic_rejection_body("temperature is not supported for this model") })

      result = described_class.send(:classify_claimed_false_error, "temperature", error)

      expect(result[:status]).to eq(:fail)
    end

    it "does not classify a 403 auth error, even with matching content (stays :fail)" do
      error = Faraday::ForbiddenError.new({ status: 403, body: anthropic_rejection_body("temperature is not supported for this model") })

      result = described_class.send(:classify_claimed_false_error, "temperature", error)

      expect(result[:status]).to eq(:fail)
    end

    it "does not classify a non-HTTP exception, even with matching message text (stays :fail)" do
      result = described_class.send(:classify_claimed_false_error, "temperature", StandardError.new("temperature is not supported"))

      expect(result[:status]).to eq(:fail)
    end

    # Bedrock's adapter raises Aws::BedrockRuntime service errors rather than Faraday errors,
    # so its claimed-false rejections are matched on the exception message instead of a parsed
    # JSON body. Wordings pinned from production Bedrock rejections as of 2026-09-01
    # (bedrock_deepseek_r1).
    describe "Bedrock ValidationException classification" do
      def bedrock_validation_exception(message)
        Aws::BedrockRuntime::Errors::ValidationException.new(nil, message)
      end

      it "classifies the production outputConfig rejection as :consistent for structured_outputs" do
        stub_forced_llm_raising(bedrock_validation_exception(
          "This model doesn't support the outputConfig field. Remove outputConfig and try again."
        ))

        result = described_class.run_for(claimed_false_entry, only: "structured_outputs")

        expect(result.fetch("structured_outputs")).to include(status: :consistent, detail: include("outputConfig"))
      end

      it "classifies a ValidationException naming temperature as unsupported as :consistent" do
        stub_forced_llm_raising(bedrock_validation_exception("This model doesn't support the temperature parameter."))

        result = described_class.run_for(claimed_false_entry, only: "temperature")

        expect(result.fetch("temperature")).to include(status: :consistent, detail: include("temperature"))
      end

      it "does not classify a ValidationException with an unrelated message (stays :fail)" do
        result = described_class.send(
          :classify_claimed_false_error, "structured_outputs",
          bedrock_validation_exception("Invocation of model ID deepseek.r1-v1:0 with on-demand throughput isn't supported.")
        )

        expect(result[:status]).to eq(:fail)
      end

      it "does not classify a ValidationException naming a different feature than the probe (stays :fail)" do
        result = described_class.send(
          :classify_claimed_false_error, "temperature",
          bedrock_validation_exception("This model doesn't support tool use.")
        )

        expect(result[:status]).to eq(:fail)
      end

      it "never classifies a claimed-true structured_outputs ValidationException, even with a matching message" do
        allow(llm).to receive(:chat).and_raise(bedrock_validation_exception(
          "This model doesn't support the outputConfig field. Remove outputConfig and try again."
        ))

        result = described_class.check_structured_outputs(entry, claimed: true)

        expect(result[:status]).to eq(:fail)
        expect(result[:detail]).not_to include("rejected by provider as declared")
      end
    end

    it "never classifies a claimed-true temperature failure, even with a matching rejection body" do
      allow(llm).to receive(:chat).and_raise(bad_request_error(anthropic_rejection_body("temperature is not supported for this model")))

      result = described_class.check_temperature(entry, claimed: true)

      expect(result[:status]).to eq(:fail)
      expect(result[:detail]).not_to include("rejected by provider as declared")
    end

    it "never classifies a claimed-true structured_outputs failure, even with a matching rejection body" do
      allow(llm).to receive(:chat).and_raise(bad_request_error(anthropic_rejection_body("response_format is not supported for this model")))

      result = described_class.check_structured_outputs(entry, claimed: true)

      expect(result[:status]).to eq(:fail)
      expect(result[:detail]).not_to include("rejected by provider as declared")
    end
  end

  # When an HTTP error body carries the provider's own error message, append it to the
  # :fail detail so a FAIL is debuggable straight from the matrix, instead of the uninformative
  # "the server responded with status 400" that Faraday::Error#message produces on its own.
  describe "FAIL diagnostics enrichment from the HTTP error body" do
    it "appends the API error message to the :fail detail when the body carries one" do
      allow(llm).to receive(:chat).and_raise(
        Faraday::BadRequestError.new({ status: 400, body: { error: { message: "some unrelated validation error" } }.to_json })
      )

      result = described_class.check_completion(entry)

      expect(result[:status]).to eq(:fail)
      expect(result[:detail]).to include("some unrelated validation error")
      expect(result[:detail]).to start_with("Faraday::BadRequestError: 400")
    end

    it "truncates the enriched detail to 180 characters" do
      allow(llm).to receive(:chat).and_raise(
        Faraday::BadRequestError.new({ status: 400, body: { error: { message: "x" * 300 } }.to_json })
      )

      result = described_class.check_completion(entry)

      expect(result[:detail].length).to be <= 180
    end

    it "falls back to the plain class/message detail when the body has no parseable API message" do
      allow(llm).to receive(:chat).and_raise(Faraday::BadRequestError.new({ status: 400, body: "not json" }))

      result = described_class.check_completion(entry)

      expect(result[:detail]).to start_with("Faraday::BadRequestError:")
    end
  end

  describe ".check_provider_managed_tools" do
    it "aggregates to :skip, naming both groups, when one tool is skipped as expensive and the rest pass" do
      result = described_class.check_provider_managed_tools(pmt_entry, only_list: nil)

      expect(result[:status]).to eq(:skip)
      expect(result[:detail]).to eq("pass: web_search; skipped: image_generation (expensive; run --only provider_managed_tools)")
    end

    it "runs image_generation, instead of skipping it, when only names provider_managed_tools alongside another capability" do
      result = described_class.check_provider_managed_tools(pmt_entry, only_list: ["completion", "provider_managed_tools"])

      expect(result[:status]).to eq(:pass)
      expect(result[:detail]).to eq("pass: web_search, image_generation")
    end

    it "does not fold a skipped tool into a passing aggregate (the bug this method's ladder fixes)" do
      result = described_class.check_provider_managed_tools(pmt_entry, only_list: nil)

      expect(result[:status]).not_to eq(:pass)
    end
  end

  # Hardens the individual checks so a :pass always means concrete evidence, not a loose
  # substring match, a vacuous zero-iteration loop, or a non-nil object standing in for proof
  # the provider actually did the thing.
  describe "hard oracles" do
    describe ".check_completion" do
      it "fails completion when the response merely contains 'ok' as a substring" do
        allow(llm).to receive(:chat).and_return(instance_double(Raif::ModelCompletion, raw_response: "not okay"))

        expect(described_class.check_completion(entry)).to include(status: :fail)
      end

      it "passes completion on an exact, trimmed, case-insensitive ok" do
        allow(llm).to receive(:chat).and_return(instance_double(Raif::ModelCompletion, raw_response: " OK \n"))

        expect(described_class.check_completion(entry)).to include(status: :pass)
      end
    end

    describe ".check_streaming" do
      it "fails streaming when the response is close to but not exactly ok, even with deltas received" do
        loose_completion = instance_double(Raif::ModelCompletion, raw_response: "okay")
        allow(llm).to receive(:chat) do |**_kwargs, &block|
          block&.call(loose_completion, "delta", :event)
          loose_completion
        end

        expect(described_class.check_streaming(entry)).to include(status: :fail)
      end
    end

    describe ".check_streaming_tool_calls" do
      it "fails streaming tool calls when iterations is zero" do
        expect(described_class.check_streaming_tool_calls(entry, iterations: 0)).to include(
          status: :fail, detail: "iterations must be >= 1"
        )
      end

      it "fails when only the unstreamed path lacks tool call evidence, even though the streamed path passes" do
        good_mc = instance_double(
          Raif::ModelCompletion, response_tool_calls: [{ "name" => "wikipedia_search", "arguments" => { "query" => "x" } }]
        )
        bad_mc = instance_double(Raif::ModelCompletion, response_tool_calls: [])

        allow(llm).to receive(:chat) do |**_kwargs, &block|
          block ? good_mc : bad_mc
        end

        expect(described_class.check_streaming_tool_calls(entry, iterations: 1)).to include(status: :fail)
      end
    end

    describe ".check_native_tool_use" do
      it "fails when the parsed tool call arguments are not a hash" do
        allow(llm).to receive(:chat).and_return(
          instance_double(Raif::ModelCompletion, response_tool_calls: [{ "name" => "wikipedia_search", "arguments" => "not a hash" }])
        )

        expect(described_class.check_native_tool_use(entry)).to include(status: :fail)
      end

      it "passes on forced tool selection plus parsed hash arguments alone, without live tool execution" do
        expect(described_class.check_native_tool_use(entry)).to include(status: :pass)
      end
    end

    describe ".check_batch_inference" do
      it "fails when an expected custom ID is missing from the results" do
        allow(batch_relation).to receive(:reload).and_return([
          instance_double(Raif::ModelCompletion, raw_response: "ok", batch_custom_id: "smoke-0")
        ])

        expect(described_class.check_batch_inference(entry, batch_timeout: 1)).to include(status: :fail)
      end

      it "fails when a result's text is close to but not exactly ok" do
        allow(batch_relation).to receive(:reload).and_return([
          instance_double(Raif::ModelCompletion, raw_response: "ok", batch_custom_id: "smoke-0"),
          instance_double(Raif::ModelCompletion, raw_response: "okay", batch_custom_id: "smoke-1")
        ])

        expect(described_class.check_batch_inference(entry, batch_timeout: 1)).to include(status: :fail)
      end

      it "fails when the batch reaches a terminal but non-success status" do
        allow(llm).to receive(:fetch_batch_status!).and_return("failed")

        expect(described_class.check_batch_inference(entry, batch_timeout: 1)).to include(status: :fail)
      end

      it "passes when the batch ends successfully with both custom IDs present and exact ok results" do
        allow(batch_relation).to receive(:reload).and_return([
          instance_double(Raif::ModelCompletion, raw_response: "ok", batch_custom_id: "smoke-0"),
          instance_double(Raif::ModelCompletion, raw_response: "ok", batch_custom_id: "smoke-1")
        ])

        expect(described_class.check_batch_inference(entry, batch_timeout: 1)).to include(status: :pass)
      end
    end

    describe ".check_images and .check_pdfs" do
      it "fails images when the nonce is absent from the response" do
        allow(llm).to receive(:chat).and_return(instance_double(Raif::ModelCompletion, raw_response: "some other text"))

        expect(described_class.check_images(entry)).to include(status: :fail)
      end

      it "fails pdfs when the nonce is absent from the response" do
        allow(llm).to receive(:chat).and_return(instance_double(Raif::ModelCompletion, raw_response: "some other text"))

        expect(described_class.check_pdfs(entry)).to include(status: :fail)
      end
    end

    describe ".check_structured_outputs recordable tagging" do
      it "does not tag a native pass (response_format_parameter present) as recordable: false" do
        native_completion = instance_double(
          Raif::ModelCompletion,
          raw_response: { joke: "j", answer: "a" }.to_json,
          response_format_parameter: "json_schema"
        )
        allow(llm).to receive(:chat).and_return(native_completion)

        result = described_class.check_structured_outputs(entry, claimed: true)

        expect(result).to include(status: :pass)
        expect(result.fetch(:recordable, true)).to eq(true)
      end

      it "tags a JSON-tool fallback pass (response_format_parameter blank) as recordable: false" do
        fallback_completion = instance_double(
          Raif::ModelCompletion,
          raw_response: { joke: "j", answer: "a" }.to_json,
          response_format_parameter: nil
        )
        allow(llm).to receive(:chat).and_return(fallback_completion)

        result = described_class.check_structured_outputs(entry, claimed: true)

        expect(result).to include(status: :pass, recordable: false)
      end
    end

    describe "provider-managed tool call evidence" do
      it "fails provider-managed web search without matching tool call evidence" do
        allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])

        expect(check_result_for("provider_managed_tools")).to include(status: :fail)
      end

      it "passes provider-managed web search with matching tool call evidence" do
        allow(model_completion).to receive(:provider_managed_tool_calls).and_return([
          { "tool_name" => "web_search", "provider_tool_call_id" => "search_1" }
        ])

        expect(check_result_for("provider_managed_tools")).to include(status: :pass)
      end

      it "fails code execution without matching tool call evidence" do
        allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])

        result = described_class.send(:check_provider_managed_tool, llm, "code_execution", only_list: nil)
        expect(result).to include(status: :fail)
      end

      it "does not treat the text '42' in the response as evidence of code execution" do
        allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])
        allow(model_completion).to receive(:raw_response).and_return("The answer is 42")

        result = described_class.send(:check_provider_managed_tool, llm, "code_execution", only_list: nil)
        expect(result).to include(status: :fail)
      end

      it "passes code execution with matching tool call evidence" do
        result = described_class.send(:check_provider_managed_tool, llm, "code_execution", only_list: nil)
        expect(result).to include(status: :pass)
      end

      it "does not treat a non-nil completion object alone as evidence of image generation" do
        allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])

        result = described_class.send(:check_provider_managed_tool, llm, "image_generation", only_list: ["provider_managed_tools"])
        expect(result).to include(status: :fail)
      end

      it "passes image generation with matching tool call evidence" do
        result = described_class.send(:check_provider_managed_tool, llm, "image_generation", only_list: ["provider_managed_tools"])
        expect(result).to include(status: :pass)
      end
    end
  end

  describe "downstream truthfulness: Smoke::ObservationRecorder never records a skipped provider_managed_tools aggregate" do
    it "leaves provider_managed_tools unrecorded when the aggregate is :skip" do
      fixture_dir = Raif::Engine.root.join("spec/fixtures/model_manifest").to_s
      recording_entry = Raif::ModelManifest.load(dir: fixture_dir).llm_entries.find { |e| e.key.to_s == "anthropic_old_model" }

      capability_results = {
        "completion" => { status: :pass, detail: "ok" },
        "provider_managed_tools" => described_class.check_provider_managed_tools(pmt_entry, only_list: nil)
      }
      expect(capability_results["provider_managed_tools"][:status]).to eq(:skip) # sanity: image_generation is expensive-skipped here

      Dir.mktmpdir("raif-checks-observation-recorder-spec") do |dir|
        model_results = [{ key: recording_entry.key.to_s, explicit: false, capabilities: capability_results }]
        entries_by_key = { recording_entry.key.to_s => recording_entry }

        Smoke::ObservationRecorder.record_all!(model_results, entries_by_key: entries_by_key, dir: dir)

        recorded = JSON.parse(File.read(File.join(dir, "anthropic.json"))).dig("models", "anthropic_old_model")
        expect(recorded).to have_key("completion")
        expect(recorded).not_to have_key("provider_managed_tools")
      end
    end
  end

  # A failing tool's detail used to embed raw model response text, truncated
  # mid-word, directly inside the aggregate's enclosing parens -- e.g. "web_search (Based on my
  # system information ... I didn't need to perfor)". These examples pin the replacement: a
  # labeled reason plus a cleanly word-boundary-truncated response preview, still inside the
  # existing "name (...)" grouping so the pass/fail/skip structure asserted above is unaffected.
  describe "per-tool failure detail formatting (Feature 2b)" do
    let(:long_response_text) do
      "Based on my system information, the current year is 2026 and I did not need to perform a web search to answer this question at all."
    end

    it "labels a failing tool's detail instead of embedding raw response text directly" do
      allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])
      allow(model_completion).to receive(:raw_response).and_return(long_response_text)

      result = described_class.send(:check_provider_managed_tool, llm, "web_search", only_list: nil)

      expect(result[:status]).to eq(:fail)
      expect(result[:detail]).to start_with('no matching provider tool call; response_text: "')
    end

    it "truncates a long response_text at a word boundary with a trailing ellipsis, never mid-word" do
      allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])
      allow(model_completion).to receive(:raw_response).and_return(long_response_text)

      result = described_class.send(:check_provider_managed_tool, llm, "web_search", only_list: nil)
      preview = result[:detail][/response_text: "(.*)\.\.\."/, 1]

      expect(preview).not_to be_nil
      expect(preview).not_to end_with(" ")
      cut_index = long_response_text.index(preview) + preview.length
      expect(long_response_text[cut_index]).to eq(" ") # the character right after the cut is a word boundary, not mid-word
    end

    it "does not truncate or add an ellipsis when the response text is already short" do
      allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])
      allow(model_completion).to receive(:raw_response).and_return("short reply")

      result = described_class.send(:check_provider_managed_tool, llm, "web_search", only_list: nil)

      expect(result[:detail]).to eq('no matching provider tool call; response_text: "short reply"')
    end

    it "keeps the per-tool detail inside the existing name (...) grouping in the full aggregate" do
      allow(model_completion).to receive(:provider_managed_tool_calls).and_return([
        { "tool_name" => "image_generation", "provider_tool_call_id" => "img_1" }
      ])
      allow(model_completion).to receive(:raw_response).and_return("short reply")

      result = described_class.check_provider_managed_tools(pmt_entry, only_list: ["provider_managed_tools"])

      expect(result[:detail]).to include('web_search (no matching provider tool call; response_text: "short reply")')
      expect(result[:detail]).to include("pass: image_generation")
    end

    it "never leaves unbalanced parens in the rendered aggregate detail, even on a long response" do
      allow(model_completion).to receive(:provider_managed_tool_calls).and_return([])
      allow(model_completion).to receive(:raw_response).and_return("x" * 200)

      result = described_class.check_provider_managed_tools(pmt_entry, only_list: nil)

      expect(result[:detail].count("(")).to eq(result[:detail].count(")"))
    end
  end

  # The web_search prompt used to ask the model to "search the web for the current
  # year and reply with it" without forbidding an answer from memory, so a model that already
  # "knows" the year could pass the prompt without invoking the tool at all -- only to then fail
  # the hard oracle (a matching provider_managed_tool_calls entry), reading as a tool failure
  # rather than the prompt-wording problem it actually was. The oracle itself is untouched here.
  describe "web_search prompt strength (Feature 2c)" do
    it "explicitly instructs the model it must perform a live search and must not answer from memory" do
      expect(llm).to receive(:chat) do |**kwargs|
        expect(kwargs[:message]).to match(/must/i)
        expect(kwargs[:message]).to match(/search/i)
        expect(kwargs[:message]).to match(/memory|prior knowledge/i)
        model_completion
      end

      described_class.send(:check_provider_managed_tool, llm, "web_search", only_list: nil)
    end
  end

  describe ".run_for_embedding" do
    it "runs the check and wraps its result under the embedding capability when no filters are given" do
      result = described_class.run_for_embedding { { status: :pass, detail: "vector_size=8 expected=8" } }

      expect(result).to eq({ "embedding" => { status: :pass, detail: "vector_size=8 expected=8" } })
    end

    it "runs the check when only includes embedding" do
      result = described_class.run_for_embedding(only: ["embedding"]) { { status: :pass, detail: "ok" } }

      expect(result.fetch("embedding")[:status]).to eq(:pass)
    end

    it "omits the capability without running the check when only excludes embedding" do
      check_ran = false

      result = described_class.run_for_embedding(only: ["completion"]) { check_ran = true }

      expect(result).to eq({})
      expect(check_ran).to eq(false)
    end

    it "reports a skip without running the check when skip includes embedding" do
      check_ran = false

      result = described_class.run_for_embedding(skip: ["embedding"]) { check_ran = true }

      expect(result).to eq({ "embedding" => { status: :skip, detail: "skipped via --skip" } })
      expect(check_ran).to eq(false)
    end
  end
end
