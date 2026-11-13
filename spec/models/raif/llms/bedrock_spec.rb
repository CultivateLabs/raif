# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Bedrock, type: :model do
  let(:llm){ Raif.llm(:bedrock_claude_5_sonnet) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
    allow(Raif.config).to receive(:bedrock_models_enabled).and_return(true)

    # To record new VCR cassettes, set real credentials here.
    stubbed_creds = Aws::Credentials.new("PLACEHOLDER_KEY", "PLACEHOLDER_SECRET")
    client = Aws::BedrockRuntime::Client.new(
      region: Raif.config.aws_bedrock_region,
      credentials: stubbed_creds
    )

    allow(llm).to receive(:bedrock_client).and_return(client)
  end

  describe "#update_model_completion" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        llm_model_key: "bedrock_claude_5_sonnet",
        model_api_name: "anthropic.claude-sonnet-5"
      )
    end

    def converse_response_with_stop_reason(stop_reason)
      Aws::BedrockRuntime::Types::ConverseResponse.new(
        output: Aws::BedrockRuntime::Types::ConverseOutput::Message.new(
          message: Aws::BedrockRuntime::Types::Message.new(
            role: "assistant",
            content: [Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "Hello")]
          )
        ),
        usage: Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15),
        stop_reason: stop_reason
      )
    end

    it "stores the stop reason and flags a max_tokens response as truncated" do
      llm.send(:update_model_completion, model_completion, converse_response_with_stop_reason("max_tokens"))

      expect(model_completion.response_finish_reason).to eq("max_tokens")
      expect(model_completion).to be_truncated
    end

    it "does not flag a normally completed response as truncated" do
      llm.send(:update_model_completion, model_completion, converse_response_with_stop_reason("end_turn"))

      expect(model_completion.response_finish_reason).to eq("end_turn")
      expect(model_completion).not_to be_truncated
    end
  end

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the Bedrock API and processes the text response", vcr: { cassette_name: "bedrock/text_response" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")
        expect(model_completion.raw_response).to eq("Hi! How can I help you today?")
        expect(model_completion.completion_tokens).to eq(12)
        expect(model_completion.prompt_tokens).to eq(14)
        expect(model_completion.total_tokens).to eq(26)
        expect(model_completion.llm_model_key).to eq("bedrock_claude_5_sonnet")
        expect(model_completion.model_api_name).to eq("us.anthropic.claude-sonnet-5")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
        expect(model_completion.messages).to eq([{ "content" => [{ "text" => "Hello" }], "role" => "user" }])
        expect(model_completion.response_array).to eq([{ "text" => "Hi! How can I help you today?" }])
      end
    end

    context "when the response format is json" do
      it "makes a request to the Bedrock API and processes the json response", vcr: { cassette_name: "bedrock/json_response" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Please give me a JSON object with a name and age. Don't include any other text in your response." }],
          system_prompt: "You are a helpful assistant.",
          response_format: :json
        )

        expect(model_completion.raw_response).to eq("{\"name\": \"John\", \"age\": 25}")
        expect(model_completion.completion_tokens).to eq(15)
        expect(model_completion.prompt_tokens).to eq(35)
        expect(model_completion.total_tokens).to eq(50)
        expect(model_completion.llm_model_key).to eq("bedrock_claude_5_sonnet")
        expect(model_completion.model_api_name).to eq("us.anthropic.claude-sonnet-5")
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.response_id).to eq(nil)
        expect(model_completion.response_array).to eq([{ "text" => "{\"name\": \"John\", \"age\": 25}" }])
      end
    end

    context "when using developer-managed tools" do
      it "extracts tool calls correctly", vcr: { cassette_name: "bedrock/developer_managed_fetch_url", allow_playback_repeats: true } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What is on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.raw_response).to eq("I'll fetch the content from the Wall Street Journal homepage.")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([
          { "text" => "I'll fetch the content from the Wall Street Journal homepage." },
          {
            "tool_use" => {
              "input" => { "url" => "https://www.wsj.com" },
              "name" => "fetch_url",
              "tool_use_id" => "tooluse_abc123"
            }
          }
        ])

        expect(model_completion.response_tool_calls).to eq([{
          "provider_tool_call_id" => "tooluse_abc123",
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])
      end
    end

    context "when using provider-managed tools" do
      it "raises Raif::Errors::UnsupportedFeatureError" do
        expect do
          llm.chat(
            messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }],
            available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
          )
        end.to raise_error(Raif::Errors::UnsupportedFeatureError)
      end
    end

    context "streaming" do
      before do
        allow(Raif.config).to receive(:streaming_update_chunk_size_threshold).and_return(10)
      end

      it "streams a text response correctly", vcr: { cassette_name: "bedrock/streaming_text" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Hello" }]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("Hi! How can I help you today?")
        expect(model_completion.completion_tokens).to eq(12)
        expect(model_completion.prompt_tokens).to eq(8)
        expect(model_completion.total_tokens).to eq(20)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{ "content" => [{ "text" => "Hello" }], "role" => "user" }])
        expect(model_completion.response_array).to eq([{ "text" => "Hi! How can I help you today?" }])

        expect(deltas).to eq(["Hi! How can", " I help you today", "?"])
      end

      it "streams a json response correctly", vcr: { cassette_name: "bedrock/streaming_json" } do
        system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key and a single `answer` key. Do not include any other text in your response outside the JSON object." # rubocop:disable Layout/LineLength

        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you you tell me a joke? Respond in json." }],
          system_prompt: system_prompt,
          response_format: :json
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("{\n    \"joke\": \"What do you call a bear with no teeth?\",\n    \"answer\": \"A gummy bear!\"\n}") # rubocop:disable Layout/LineLength
        expect(model_completion.parsed_response).to eq({
          "joke" => "What do you call a bear with no teeth?",
          "answer" => "A gummy bear!"
        })
        expect(model_completion.completion_tokens).to eq(34)
        expect(model_completion.prompt_tokens).to eq(70)
        expect(model_completion.total_tokens).to eq(104)
        expect(model_completion).to be_persisted
        expect(model_completion.response_array).to eq([{
          "text" => "{\n    \"joke\": \"What do you call a bear with no teeth?\",\n    \"answer\": \"A gummy bear!\"\n}"
        }])

        expect(deltas).to eq([
          "{\n    \"joke\": \"",
          "What do you call",
          " a bear with no teeth?",
          "\",\n    \"answer\": \"A",
          " gummy bear!\"",
          "\n}"
        ])
      end

      it "streams a response with tool calls correctly", vcr: { cassette_name: "bedrock/streaming_tool_calls" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("I'll help you fetch the content from the Wall Street Journal's homepage.")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])

        expect(model_completion.response_tool_calls).to eq([{
          "provider_tool_call_id" => "tooluse_JI4D_oKCRq6GPOIBN_z-_A",
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])

        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{
          "role" => "user",
          "content" => [{
            "text" => "What's on the homepage of https://www.wsj.com today?"
          }]
        }])

        expect(deltas).to eq(["I'll help you fetch the content", " from the Wall Street Journal's", " homepage."])
      end
    end

    context "when streaming is disabled for the model (known-broken on Bedrock Converse)" do
      let(:gpt_oss_llm){ Raif.llm(:bedrock_gpt_oss_120b) }
      let(:bedrock_double){ instance_double(Aws::BedrockRuntime::Client) }

      let(:non_streaming_response) do
        Aws::BedrockRuntime::Types::ConverseResponse.new(
          output: Aws::BedrockRuntime::Types::ConverseOutput::Message.new(
            message: Aws::BedrockRuntime::Types::Message.new(
              role: "assistant",
              content: [Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "Hi!")]
            )
          ),
          usage: Aws::BedrockRuntime::Types::TokenUsage.new(
            input_tokens: 5,
            output_tokens: 2,
            total_tokens: 7
          ),
          stop_reason: "end_turn"
        )
      end

      before do
        allow(gpt_oss_llm).to receive(:bedrock_client).and_return(bedrock_double)
      end

      it "takes the non-streaming path even when a streaming block is given" do
        expect(bedrock_double).to receive(:converse).and_return(non_streaming_response)
        expect(bedrock_double).not_to receive(:converse_stream)

        deltas = []
        model_completion = gpt_oss_llm.chat(messages: [{ role: "user", content: "Hello" }]) do |_mc, delta, _event|
          deltas << delta
        end

        expect(model_completion.stream_response).to eq(false)
        expect(model_completion.raw_response).to eq("Hi!")
        expect(deltas).to be_empty
      end
    end
  end

  describe "#build_request_parameters" do
    let(:image_path) { Raif::Engine.root.join("spec/fixtures/files/cultivate.png") }
    let(:file_path) { Raif::Engine.root.join("spec/fixtures/files/test.pdf") }

    let(:messages) do
      [
        {
          "role" => "user",
          "content" => [
            { "text" => "Hello" },
            {
              "image" => {
                "format" => "png",
                "source" => {
                  "tmp_base64_data" => Base64.strict_encode64(File.read(image_path))
                }
              }
            },
            {
              "document" => {
                "format" => "pdf",
                "name" => "test",
                "source" => {
                  "tmp_base64_data" => Base64.strict_encode64(File.read(file_path))
                }
              }
            }
          ]
        }
      ]
    end
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages:,
        system_prompt: "You are a helpful assistant.",
        llm_model_key: "bedrock_claude_5_sonnet",
        model_api_name: "us.anthropic.claude-sonnet-5"
      )
    end

    it "builds the correct parameters" do
      parameters = llm.send(:build_request_parameters, model_completion)
      expect(parameters[:model_id]).to eq("us.anthropic.claude-sonnet-5")
      expect(parameters[:inference_config][:max_tokens]).to eq(8192)

      # It replaces the tmp_base64_data with bytes
      expect(parameters[:messages]).to eq([
        {
          role: "user",
          content: [
            { text: "Hello" },
            {
              image: {
                format: "png",
                source: {
                  bytes: File.binread(image_path)
                }
              }
            },
            {
              document: {
                format: "pdf",
                name: "test",
                source: {
                  bytes: File.binread(file_path)
                }
              }
            }
          ]
        }
      ])
    end

    it "omits temperature for a model that does not support it" do
      parameters = llm.send(:build_request_parameters, model_completion)

      expect(parameters[:inference_config]).not_to have_key(:temperature)
    end

    context "when the model supports temperature" do
      let(:llm){ Raif.llm(:bedrock_claude_4_5_haiku) }

      def inference_config_for(temperature)
        model_completion = Raif::ModelCompletion.new(
          messages: [{ "role" => "user", "content" => [{ "text" => "Hello" }] }],
          llm_model_key: "bedrock_claude_4_5_haiku",
          model_api_name: "us.anthropic.claude-haiku-4-5-20251001-v1:0",
          temperature: temperature
        )
        llm.send(:build_request_parameters, model_completion)[:inference_config]
      end

      it "sends the completion's temperature" do
        expect(inference_config_for(0.2)).to eq(max_tokens: 8192, temperature: 0.2)
      end

      it "sends a temperature of zero" do
        expect(inference_config_for(0)).to eq(max_tokens: 8192, temperature: 0.0)
      end

      it "sends the default temperature when the completion has none" do
        expect(inference_config_for(nil)).to eq(max_tokens: 8192, temperature: 0.7)
      end
    end
  end

  describe "#resolve_model_api_name" do
    it "prefixes non-gpt-oss model ids when a prefix is configured" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")

      resolved = llm.send(:resolve_model_api_name, "anthropic.claude-sonnet-5")
      expect(resolved).to eq("us.anthropic.claude-sonnet-5")
    end

    it "does not prefix gpt-oss model ids when a prefix is configured" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")

      resolved = llm.send(:resolve_model_api_name, "openai.gpt-oss-20b-1:0")
      expect(resolved).to eq("openai.gpt-oss-20b-1:0")
    end

    it "does not prefix deepseek model ids when a prefix is configured" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")

      resolved = llm.send(:resolve_model_api_name, "deepseek.v3.2")
      expect(resolved).to eq("deepseek.v3.2")
    end

    it "does not double-prefix model ids that already have the configured prefix" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")

      resolved = llm.send(:resolve_model_api_name, "us.anthropic.claude-sonnet-5")
      expect(resolved).to eq("us.anthropic.claude-sonnet-5")
    end

    it "does not prefix model ids that already name a different inference profile" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")

      expect(llm.send(:resolve_model_api_name, "global.anthropic.claude-sonnet-5-5")).to eq("global.anthropic.claude-sonnet-5-5")
      expect(llm.send(:resolve_model_api_name, "eu.anthropic.claude-sonnet-5")).to eq("eu.anthropic.claude-sonnet-5")
    end

    it "resolves every Bedrock manifest api_name to at most one inference profile prefix" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")
      profiles = described_class::INFERENCE_PROFILE_PREFIXES
      bedrock_entries = Raif::ModelManifest.load.llm_entries.select { |entry| entry.adapter_class_name == described_class.name }

      expect(bedrock_entries).not_to be_empty
      bedrock_entries.each do |entry|
        resolved = llm.send(:resolve_model_api_name, entry.api_name)
        expect(profiles).not_to include(resolved.split(".")[1]), "#{entry.key} resolves to #{resolved}"
      end
    end
  end

  describe "blank response retry behavior" do
    let(:blank_response) do
      content = [Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "")]
      message = Aws::BedrockRuntime::Types::Message.new(role: "assistant", content: content)
      output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: message)
      usage = Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 100, output_tokens: 0, total_tokens: 100)
      Aws::BedrockRuntime::Types::ConverseResponse.new(output: output, usage: usage, stop_reason: "end_turn")
    end

    let(:successful_response) do
      content = [Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "Here is the answer.")]
      message = Aws::BedrockRuntime::Types::Message.new(role: "assistant", content: content)
      output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: message)
      usage = Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 100, output_tokens: 50, total_tokens: 150)
      Aws::BedrockRuntime::Types::ConverseResponse.new(output: output, usage: usage, stop_reason: "end_turn")
    end

    before do
      allow(Raif.config).to receive(:llm_api_requests_enabled).and_return(true)
      allow(Raif.config).to receive(:llm_request_max_retries).and_return(2)
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return(nil)
    end

    it "retries a blank response and succeeds on a subsequent attempt" do
      call_count = 0
      mock_client = instance_double(Aws::BedrockRuntime::Client)
      allow(llm).to receive(:bedrock_client).and_return(mock_client)
      allow(mock_client).to receive(:converse) do
        call_count += 1
        call_count == 1 ? blank_response : successful_response
      end

      mc = llm.chat(messages: [{ role: "user", content: "Hello" }])

      expect(mc.completed?).to be true
      expect(mc.raw_response).to eq("Here is the answer.")
      expect(mc.retry_count).to eq(1)
      expect(call_count).to eq(2)
    end

    it "fails after exhausting retries on persistent blank responses" do
      mock_client = instance_double(Aws::BedrockRuntime::Client)
      allow(llm).to receive(:bedrock_client).and_return(mock_client)
      allow(mock_client).to receive(:converse).and_return(blank_response)

      expect do
        llm.chat(messages: [{ role: "user", content: "Hello" }])
      end.to raise_error(Raif::Errors::BlankResponseError)

      mc = Raif::ModelCompletion.newest_first.first
      expect(mc.failed?).to be true
      expect(mc.retry_count).to eq(2)
    end
  end

  describe "#retriable_exceptions" do
    it "includes the transient AWS SDK exceptions in addition to the default retriable exceptions" do
      exceptions = llm.send(:retriable_exceptions)

      expect(exceptions).to include(
        Aws::BedrockRuntime::Errors::ThrottlingException,
        Aws::BedrockRuntime::Errors::ServiceUnavailableException,
        Aws::BedrockRuntime::Errors::InternalServerException,
        Aws::BedrockRuntime::Errors::ModelTimeoutException,
        Aws::BedrockRuntime::Errors::ModelNotReadyException,
        Seahorse::Client::NetworkingError
      )

      Raif.config.llm_request_retriable_exceptions.each do |exception|
        expect(exceptions).to include(exception)
      end
    end

    # ServiceError is the base class for every Bedrock error, transient or not. Retrying a
    # ValidationException only delays the error the caller has to see.
    it "leaves the errors that will not pass on their own alone" do
      exceptions = llm.send(:retriable_exceptions)

      expect(exceptions).not_to include(Aws::BedrockRuntime::Errors::ServiceError)
      expect(exceptions).not_to include(Aws::BedrockRuntime::Errors::ValidationException)
      expect(exceptions).not_to include(Aws::BedrockRuntime::Errors::AccessDeniedException)
    end

    # The override was previously dead: #retry_with_backoff did not pass it, so TransientRetry
    # fell back to the config list, which names no AWS error at all.
    it "is what the retry actually runs on" do
      mock_client = instance_double(Aws::BedrockRuntime::Client)
      allow(llm).to receive(:bedrock_client).and_return(mock_client)
      allow(mock_client).to receive(:converse).and_raise(Aws::BedrockRuntime::Errors::ThrottlingException.new(nil, "slow down"))
      allow(Raif::Utils::TransientRetry).to receive(:call).and_call_original

      expect do
        llm.chat(messages: [{ role: "user", content: "Hello" }])
      end.to raise_error(Aws::BedrockRuntime::Errors::ThrottlingException)

      expect(Raif::Utils::TransientRetry).to have_received(:call)
        .with(hash_including(retriable_exceptions: llm.send(:retriable_exceptions)))
      # The initial attempt plus Raif.config.llm_request_max_retries.
      expect(mock_client).to have_received(:converse).exactly(3).times
    end
  end

  describe "refusal handling" do
    it "raises RefusalError without retrying when a content filter blocks the output" do
      message = Aws::BedrockRuntime::Types::Message.new(role: "assistant", content: [])
      output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: message)
      usage = Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 4, output_tokens: 0, total_tokens: 4)
      blocked_response = Aws::BedrockRuntime::Types::ConverseResponse.new(output: output, usage: usage, stop_reason: "content_filtered")
      mock_client = instance_double(Aws::BedrockRuntime::Client)
      allow(llm).to receive(:bedrock_client).and_return(mock_client)
      allow(mock_client).to receive(:converse).and_return(blocked_response)

      expect do
        llm.chat(messages: [{ role: "user", content: "Hello" }])
      end.to raise_error(Raif::Errors::RefusalError, /\(finish reason: content_filtered\)\z/)

      expect(mock_client).to have_received(:converse).once
    end
  end

  describe "nil response handling" do
    it "raises BlankResponseError when the API returns nil" do
      mock_client = instance_double(Aws::BedrockRuntime::Client)
      allow(llm).to receive(:bedrock_client).and_return(mock_client)
      allow(mock_client).to receive(:converse).and_return(nil)

      expect do
        llm.chat(messages: [{ role: "user", content: "Hello" }])
      end.to raise_error(Raif::Errors::BlankResponseError)

      mc = Raif::ModelCompletion.newest_first.first
      expect(mc.failed?).to be true
    end
  end

  describe "#build_tools_parameter" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: llm.key.to_s,
        model_api_name: llm.api_name,
        available_model_tools: available_model_tools,
        response_format: response_format,
        source: source
      )
    end
    let(:response_format) { "text" }
    let(:source) { nil }

    context "with no tools and text response format" do
      let(:available_model_tools) { [] }

      it "returns an empty hash" do
        result = llm.send(:build_tools_parameter, model_completion)
        expect(result).to eq({})
      end
    end

    context "with JSON response format and schema" do
      # A model without native structured outputs, so the json_response tool fallback applies.
      let(:llm) { Raif.llm(:bedrock_amazon_nova_pro) }
      let(:available_model_tools) { [] }
      let(:response_format) { "json" }
      let(:source) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      it "includes json_response tool when JSON format is requested with schema" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq({
          tools: [{
            tool_spec: {
              name: "json_response",
              description: "Generate a structured JSON response based on the provided schema.",
              input_schema: {
                json: {
                  type: "object",
                  additionalProperties: false,
                  required: ["joke", "answer"],
                  properties: {
                    joke: { type: "string" },
                    answer: { type: "string" }
                  }
                }
              }
            }
          }]
        })
      end
    end

    context "with developer-managed tools" do
      let(:available_model_tools) { [Raif::TestModelTool] }

      it "formats developer-managed tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq({
          tools: [{
            tool_spec: {
              name: "test_model_tool",
              description: "Mock Tool Description",
              input_schema: {
                json: {
                  type: "object",
                  additionalProperties: false,
                  required: ["items"],
                  properties: {
                    items: {
                      type: "array",
                      items: {
                        type: "object",
                        additionalProperties: false,
                        properties: {
                          title: { type: "string", description: "The title of the item" },
                          description: { type: "string" }
                        },
                        required: ["title", "description"]
                      }
                    }
                  }
                }
              }
            }
          }]
        })
      end
    end

    context "with provider-managed tools" do
      context "with WebSearch tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::WebSearch] }

        it "raises UnsupportedFeatureError for provider-managed tools" do
          expect do
            llm.send(:build_tools_parameter, model_completion)
          end.to raise_error(Raif::Errors::UnsupportedFeatureError, /Invalid provider-managed tool/)
        end
      end

      context "with CodeExecution tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::CodeExecution] }

        it "raises UnsupportedFeatureError for provider-managed tools" do
          expect do
            llm.send(:build_tools_parameter, model_completion)
          end.to raise_error(Raif::Errors::UnsupportedFeatureError, /Invalid provider-managed tool/)
        end
      end

      context "with ImageGeneration tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::ImageGeneration] }

        it "raises UnsupportedFeatureError for provider-managed tools" do
          expect do
            llm.send(:build_tools_parameter, model_completion)
          end.to raise_error(Raif::Errors::UnsupportedFeatureError, /Invalid provider-managed tool/)
        end
      end
    end

    context "with mixed tool types and JSON response" do
      let(:llm) { Raif.llm(:bedrock_amazon_nova_pro) }
      let(:available_model_tools) { [Raif::TestModelTool] }
      let(:response_format) { "json" }
      let(:source) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      it "includes json_response tool and formats developer-managed tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq({
          tools: [
            {
              tool_spec: {
                name: "json_response",
                description: "Generate a structured JSON response based on the provided schema.",
                input_schema: {
                  json: {
                    type: "object",
                    additionalProperties: false,
                    required: ["joke", "answer"],
                    properties: {
                      joke: { type: "string" },
                      answer: { type: "string" }
                    }
                  }
                }
              }
            },
            {
              tool_spec: {
                name: "test_model_tool",
                description: "Mock Tool Description",
                input_schema: {
                  json: {
                    type: "object",
                    additionalProperties: false,
                    required: ["items"],
                    properties: {
                      items: {
                        type: "array",
                        items: {
                          type: "object",
                          additionalProperties: false,
                          properties: {
                            title: { type: "string", description: "The title of the item" },
                            description: { type: "string" }
                          },
                          required: ["title", "description"]
                        }
                      }
                    }
                  }
                }
              }
            }
          ]
        })
      end
    end
  end

  describe "#format_messages" do
    it "formats the messages correctly with a string as the content" do
      messages = [{ "role" => "user", "content" => "Hello" }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello" }] }])
    end

    it "formats the messages correctly with an array as the content" do
      messages = [{ "role" => "user", "content" => ["Hello", "World"] }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "content" => [
            { "text" => "Hello" },
            { "text" => "World" }
          ]
        }
      ])
    end

    it "formats the messages correctly with an image" do
      image_path = Raif::Engine.root.join("spec/fixtures/files/cultivate.png")
      image = Raif::ModelImageInput.new(input: image_path)
      messages = [{
        "role" => "user",
        "content" => [
          { "text" => "Hello" },
          image
        ]
      }]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "content" => [
            { "text" => "Hello" },
            {
              "image" => {
                "format" => "png",
                "source" => {
                  "tmp_base64_data" => Base64.strict_encode64(File.read(image_path))
                }
              }
            }
          ]
        }
      ])
    end

    it "formats the messages correctly with a file" do
      file_path = Raif::Engine.root.join("spec/fixtures/files/test.pdf")
      file = Raif::ModelFileInput.new(input: file_path)
      messages = [{
        "role" => "user",
        "content" => [
          { "text" => "Hello" },
          file
        ]
      }]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "content" => [
            { "text" => "Hello" },
            {
              "document" => {
                "format" => "pdf",
                "name" => "test",
                "source" => {
                  "tmp_base64_data" => Base64.strict_encode64(File.read(file_path))
                }
              }
            }
          ]
        }
      ])
    end

    it "raises an error when trying to use image_url" do
      image = Raif::ModelImageInput.new(url: "https://example.com/image.png")
      messages = [{ "role" => "user", "content" => [image] }]
      expect { llm.format_messages(messages) }.to raise_error(Raif::Errors::UnsupportedFeatureError)
    end

    it "raises an error when trying to use file_url" do
      file = Raif::ModelFileInput.new(url: "https://example.com/file.pdf")
      messages = [{ "role" => "user", "content" => [file] }]
      expect { llm.format_messages(messages) }.to raise_error(Raif::Errors::UnsupportedFeatureError)
    end

    it "consolidates consecutive user-role tool results and user messages" do
      messages = [
        {
          "type" => "tool_call_result",
          "provider_tool_call_id" => "call_123",
          "name" => "fetch_url",
          "result" => { "content" => "Page content here" }
        },
        { "role" => "user", "content" => "Summarize it" }
      ]

      expect(llm.format_messages(messages)).to eq([
        {
          "role" => "user",
          "content" => [
            {
              "tool_result" => {
                "tool_use_id" => "call_123",
                "content" => [{ "json" => { "content" => "Page content here" } }]
              }
            },
            { "text" => "Summarize it" }
          ]
        }
      ])
    end

    it "leaves non-consecutive same-role messages unchanged" do
      messages = [
        { "role" => "user", "content" => "First" },
        { "role" => "assistant", "content" => "Second" },
        { "role" => "user", "content" => "Third" }
      ]

      expect(llm.format_messages(messages)).to eq([
        { "role" => "user", "content" => [{ "text" => "First" }] },
        { "role" => "assistant", "content" => [{ "text" => "Second" }] },
        { "role" => "user", "content" => [{ "text" => "Third" }] }
      ])
    end
  end

  describe "#extract_response_tool_calls" do
    let(:tool_use_block) do
      Aws::BedrockRuntime::Types::ContentBlock.new(
        tool_use: Aws::BedrockRuntime::Types::ToolUseBlock.new(
          tool_use_id: "tooluse_abc123",
          name: "fetch_url",
          input: input_value
        )
      )
    end

    let(:response) do
      message = Aws::BedrockRuntime::Types::Message.new(role: "assistant", content: [tool_use_block])
      output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: message)
      usage = Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 1, output_tokens: 1, total_tokens: 2)
      Aws::BedrockRuntime::Types::ConverseResponse.new(output: output, usage: usage, stop_reason: "tool_use")
    end

    context "when tool_use.input is already a Hash (the normal SDK-deserialized case)" do
      let(:input_value) { { "url" => "https://www.wsj.com" } }

      it "returns the Hash as-is" do
        tool_calls = llm.extract_response_tool_calls(response)

        expect(tool_calls).to eq([{
          "provider_tool_call_id" => "tooluse_abc123",
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])
      end
    end

    context "when tool_use.input defensively arrives as a well-formed JSON string" do
      let(:input_value) { "{\"url\": \"https://www.wsj.com\"}" }

      it "parses the JSON string into a Hash" do
        tool_calls = llm.extract_response_tool_calls(response)

        expect(tool_calls).to eq([{
          "provider_tool_call_id" => "tooluse_abc123",
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])
      end
    end

    context "when tool_use.input defensively arrives as a malformed JSON string" do
      let(:input_value) { "{\n \" \"06    \" States president 202" }

      it "leaves the raw String so downstream validation can reject it" do
        tool_calls = llm.extract_response_tool_calls(response)

        expect(tool_calls).to eq([{
          "provider_tool_call_id" => "tooluse_abc123",
          "name" => "fetch_url",
          "arguments" => "{\n \" \"06    \" States president 202"
        }])
      end
    end

    it "returns nil when there are no tool_use blocks in the response" do
      text_block = Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: "Hello")
      message = Aws::BedrockRuntime::Types::Message.new(role: "assistant", content: [text_block])
      output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: message)
      usage = Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 1, output_tokens: 1, total_tokens: 2)
      text_only_response = Aws::BedrockRuntime::Types::ConverseResponse.new(output: output, usage: usage, stop_reason: "end_turn")

      expect(llm.extract_response_tool_calls(text_only_response)).to be_nil
    end
  end

  describe "#build_forced_tool_choice" do
    it "returns the correct format for forcing a specific tool" do
      result = llm.build_forced_tool_choice("agent_final_answer")
      expect(result).to eq({ tool: { name: "agent_final_answer" } })
    end
  end

  describe "#build_required_tool_choice" do
    it "returns the correct format for requiring any tool" do
      expect(llm.build_required_tool_choice).to eq({ any: {} })
    end
  end

  describe "#build_request_parameters with prompt caching" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: [{ text: "Hello" }] }],
        llm_model_key: "bedrock_claude_5_sonnet",
        model_api_name: "us.anthropic.claude-sonnet-5",
        temperature: 0.8,
        response_format: "text",
        system_prompt: "You are a helpful assistant"
      )
    end

    let(:parameters) { llm.send(:build_request_parameters, model_completion) }

    context "when prompt caching is enabled" do
      before { model_completion.bedrock_prompt_caching_enabled = true }

      it "appends a cache_point to the system prompt" do
        expect(parameters[:system]).to eq([
          { text: "You are a helpful assistant" },
          { cache_point: { type: "default" } }
        ])
      end

      it "appends a cache_point to the last message content" do
        expect(parameters[:messages].last[:content].last).to eq({ cache_point: { type: "default" } })
      end
    end

    context "when prompt caching is not enabled" do
      it "does not include cache_point in the system prompt" do
        expect(parameters[:system]).to eq([{ text: "You are a helpful assistant" }])
      end

      it "does not include cache_point in the messages" do
        expect(parameters[:messages].last[:content]).not_to include(hash_including(cache_point: anything))
      end
    end
  end

  describe "#build_request_parameters with native structured outputs" do
    let(:test_task){ Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

    context "with a json_response_schema and a supporting model" do
      let(:llm){ Raif.llm(:bedrock_claude_4_5_sonnet) }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: [{ text: "Tell me a joke" }] }],
          llm_model_key: "bedrock_claude_4_5_sonnet",
          model_api_name: "anthropic.claude-sonnet-4-5-20250929-v1:0",
          response_format: "json",
          source: test_task
        )
      end

      it "emits output_config.text_format with the source's schema as a JSON-encoded string nested under structure.json_schema" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:output_config]).to eq({
          text_format: {
            type: "json_schema",
            structure: {
              json_schema: {
                name: "json_response_schema",
                description: "Generate a structured JSON response based on the provided schema.",
                schema: JSON.generate(model_completion.json_response_schema)
              }
            }
          }
        })
      end

      it "does NOT inject a json_response function tool" do
        params = llm.send(:build_request_parameters, model_completion)
        tool_specs = params.dig(:tool_config, :tools) || []
        tool_names = tool_specs.map { |t| t.dig(:tool_spec, :name) }
        expect(tool_names).not_to include("json_response")
      end

      it "does NOT send the strict flag, which only the OpenAI GPT model cards call for" do
        params = llm.send(:build_request_parameters, model_completion)
        expect(params).not_to have_key(:additional_model_request_fields)
      end

      it "sets model_completion.response_format_parameter to 'json_schema'" do
        llm.send(:build_request_parameters, model_completion)
        expect(model_completion.response_format_parameter).to eq("json_schema")
      end

      # Bedrock does not validate the schema itself -- it forwards the Anthropic
      # validator's message verbatim -- so the same strict subset applies here.
      it "sends no constraint the structured-output validator rejects" do
        allow(model_completion).to receive(:json_response_schema).and_return({
          type: "object",
          additionalProperties: false,
          properties: {
            probability: { type: "integer", minimum: 0, maximum: 100 },
            probabilities: { type: "array", minItems: 3, maxItems: 3, items: { type: "string" } }
          },
          required: ["probability", "probabilities"]
        })

        params = llm.send(:build_request_parameters, model_completion)
        schema = JSON.parse(params.dig(:output_config, :text_format, :structure, :json_schema, :schema))

        expect(schema.to_s).not_to match(/maximum|minimum|maxItems|uniqueItems|multipleOf/)
        expect(schema.dig("properties", "probabilities", "minItems")).to eq(1)
        expect(schema.dig("properties", "probability", "description")).to eq("Must be at least 0. Must be at most 100.")
      end
    end

    context "with a json_response_schema on an OpenAI GPT model" do
      let(:llm){ Raif.llm(:bedrock_gpt_6_luna) }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: [{ text: "Tell me a joke" }] }],
          llm_model_key: "bedrock_gpt_6_luna",
          model_api_name: "openai.gpt-6-luna",
          response_format: "json",
          source: test_task
        )
      end

      it "sends additional_model_request_fields.text.format.strict alongside output_config" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:additional_model_request_fields]).to eq({ text: { format: { strict: true } } })
        expect(params.dig(:output_config, :text_format, :type)).to eq("json_schema")
        expect(model_completion.response_format_parameter).to eq("json_schema")
      end

      it "sends the flag on streaming requests too" do
        model_completion.stream_response = true

        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:additional_model_request_fields]).to eq({ text: { format: { strict: true } } })
      end

      it "does not send the flag without a json_response_schema" do
        model_completion.response_format = "text"
        model_completion.source = nil

        params = llm.send(:build_request_parameters, model_completion)

        expect(params).not_to have_key(:additional_model_request_fields)
      end
    end

    it "sends the strict flag for exactly the Bedrock GPT models whose model cards call for it" do
      keys = Raif.available_llm_keys.select { |key| Raif.llm(key).supports_strict_structured_outputs? }

      expect(keys.map(&:to_s)).to match_array(%w[
        bedrock_gpt_5_6_sol bedrock_gpt_5_6_terra bedrock_gpt_5_6_luna
        bedrock_gpt_6_sol bedrock_gpt_6_luna bedrock_gpt_6_astra
        bedrock_gpt_6_1_sol bedrock_gpt_6_1_terra
      ])
    end

    context "with a json_response_schema but a non-supporting model" do
      let(:llm){ Raif.llm(:bedrock_amazon_nova_pro) }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: [{ text: "Tell me a joke" }] }],
          llm_model_key: "bedrock_amazon_nova_pro",
          model_api_name: "amazon.nova-pro-v1:0",
          response_format: "json",
          source: test_task
        )
      end

      it "does NOT include output_config" do
        params = llm.send(:build_request_parameters, model_completion)
        expect(params).not_to have_key(:output_config)
      end

      it "still injects the json_response function tool (existing fallback)" do
        params = llm.send(:build_request_parameters, model_completion)
        tool_specs = params.dig(:tool_config, :tools) || []
        tool_names = tool_specs.map { |t| t.dig(:tool_spec, :name) }
        expect(tool_names).to include("json_response")
      end
    end

    context "without a json_response_schema on a supporting model" do
      let(:llm){ Raif.llm(:bedrock_claude_4_5_sonnet) }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: [{ text: "Hello" }] }],
          llm_model_key: "bedrock_claude_4_5_sonnet",
          model_api_name: "anthropic.claude-sonnet-4-5-20250929-v1:0",
          response_format: "text"
        )
      end

      it "does NOT include output_config (no schema to enforce)" do
        params = llm.send(:build_request_parameters, model_completion)
        expect(params).not_to have_key(:output_config)
      end
    end

    context "with a json_response_schema on a Claude 4.7-and-later model" do
      let(:llm){ Raif.llm(:bedrock_claude_5_sonnet) }
      let(:scored_task) do
        Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)).tap do |task|
          allow(task).to receive(:json_response_schema).and_return({
            type: "object",
            additionalProperties: false,
            required: ["score"],
            properties: {
              score: { type: "number", minimum: 0, maximum: 1 }
            }
          })
        end
      end
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: [{ text: "Score this" }] }],
          llm_model_key: "bedrock_claude_5_sonnet",
          model_api_name: "anthropic.claude-sonnet-5",
          response_format: "json",
          source: scored_task
        )
      end

      def converse_text_response(text, stop_reason:)
        Aws::BedrockRuntime::Types::ConverseResponse.new(
          output: Aws::BedrockRuntime::Types::ConverseOutput::Message.new(
            message: Aws::BedrockRuntime::Types::Message.new(
              role: "assistant",
              content: [Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: text)]
            )
          ),
          usage: Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15),
          stop_reason: stop_reason
        )
      end

      it "uses output_config and no json_response tool" do
        params = llm.send(:build_request_parameters, model_completion)
        tool_names = (params.dig(:tool_config, :tools) || []).map { |t| t.dig(:tool_spec, :name) }

        expect(params).to have_key(:output_config)
        expect(tool_names).not_to include("json_response")
      end

      let(:bedrock_client) { instance_double(Aws::BedrockRuntime::Client) }

      before do
        allow(llm).to receive(:bedrock_client).and_return(bedrock_client)
      end

      def stub_converse(text, stop_reason:)
        allow(bedrock_client).to receive(:converse).and_return(converse_text_response(text, stop_reason: stop_reason))
      end

      it "accepts native output that satisfies the original schema" do
        stub_converse({ score: 0.5 }.to_json, stop_reason: "end_turn")

        expect { llm.perform_model_completion!(model_completion) }.not_to raise_error
      end

      it "rejects native output that violates constraints removed from the provider schema" do
        stub_converse({ score: 2 }.to_json, stop_reason: "end_turn")

        expect do
          llm.perform_model_completion!(model_completion)
        end.to raise_error(Raif::Errors::InvalidJsonResponseError, /score/)

        expect(model_completion.reload.raw_response).to eq({ score: 2 }.to_json)
      end

      it "reports JSON cut off at the output limit as a truncation" do
        stub_converse("{\"sco", stop_reason: "max_tokens")

        expect do
          llm.perform_model_completion!(model_completion)
        end.to raise_error(Raif::Errors::TruncatedResponseError, /cut off at the output limit \(finish reason: max_tokens\)/)
      end

      context "when streaming" do
        let(:model_completion) do
          Raif::ModelCompletion.new(
            messages: [{ role: "user", content: [{ text: "Score this" }] }],
            llm_model_key: "bedrock_claude_5_sonnet",
            model_api_name: "anthropic.claude-sonnet-5",
            response_format: "json",
            source: scored_task,
            stream_response: true
          )
        end

        def stub_converse_stream(text)
          types = Aws::BedrockRuntime::Types
          events = [
            types::MessageStartEvent.new(role: "assistant", event_type: :message_start),
            types::ContentBlockDeltaEvent.new(
              content_block_index: 0,
              delta: types::ContentBlockDelta::Text.new(text: text),
              event_type: :content_block_delta
            ),
            types::MessageStopEvent.new(stop_reason: "end_turn", event_type: :message_stop),
            types::ConverseStreamMetadataEvent.new(
              usage: types::TokenUsage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15),
              event_type: :metadata
            )
          ]

          allow(bedrock_client).to receive(:converse_stream) do |_params, &setup|
            handlers = {}
            stream = double("stream")
            allow(stream).to receive(:on_error_event)
            allow(stream).to receive(:on_event) { |&handler| handlers[:event] = handler }
            setup.call(stream)
            events.each { |event| handlers[:event].call(event) }
          end
        end

        it "records the stream's usage before rejecting output that violates the original schema" do
          stub_converse_stream({ score: 2 }.to_json)

          expect do
            llm.perform_model_completion!(model_completion) { |_mc, _delta, _event| nil }
          end.to raise_error(Raif::Errors::InvalidJsonResponseError, /score/)

          model_completion.reload
          expect(model_completion.raw_response).to eq({ score: 2 }.to_json)
          expect(model_completion.prompt_tokens).to eq(10)
          expect(model_completion.completion_tokens).to eq(5)
          expect(model_completion.total_tokens).to eq(15)
        end

        it "accepts streamed output that satisfies the original schema" do
          stub_converse_stream({ score: 0.5 }.to_json)

          expect do
            llm.perform_model_completion!(model_completion) { |_mc, _delta, _event| nil }
          end.not_to raise_error
          expect(model_completion.reload.total_tokens).to eq(15)
        end
      end
    end
  end

  describe "#build_request_parameters with required tool_choice" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: [{ text: "Hello" }] }],
        llm_model_key: "bedrock_anthropic_claude_4_sonnet",
        model_api_name: "us.anthropic.claude-sonnet-4-20250514-v1:0",
        temperature: 0.8,
        response_format: "text",
        system_prompt: "You are a helpful assistant",
        available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::AgentFinalAnswer],
        tool_choice: "required"
      )
    end

    let(:parameters) { llm.send(:build_request_parameters, model_completion) }

    it "sets tool_config tool_choice to the required format" do
      expect(parameters[:tool_config][:tool_choice]).to eq({ any: {} })
    end

    it "does not include parallel_tool_calls" do
      expect(parameters).not_to have_key(:parallel_tool_calls)
    end
  end

  describe "#extract_json_response normalization" do
    let(:schema) do
      {
        type: "object",
        additionalProperties: false,
        required: ["joke", "answer"],
        properties: {
          joke: { type: "string" },
          answer: { type: "string" }
        }
      }
    end

    let(:model_completion) do
      instance_double(Raif::ModelCompletion, json_response_schema: schema)
    end

    def response_with_tool_input(input, text_blocks: [])
      content = text_blocks.map { |text| Aws::BedrockRuntime::Types::ContentBlock::Text.new(text: text) }
      content << Aws::BedrockRuntime::Types::ContentBlock.new(
        tool_use: Aws::BedrockRuntime::Types::ToolUseBlock.new(
          tool_use_id: "tooluse_abc123",
          name: "json_response",
          input: input
        )
      )

      message = Aws::BedrockRuntime::Types::Message.new(role: "assistant", content: content)
      output = Aws::BedrockRuntime::Types::ConverseOutput::Message.new(message: message)
      usage = Aws::BedrockRuntime::Types::TokenUsage.new(input_tokens: 1, output_tokens: 1, total_tokens: 2)
      Aws::BedrockRuntime::Types::ConverseResponse.new(output: output, usage: usage, stop_reason: "tool_use")
    end

    it "passes a schema-conforming input through unchanged" do
      resp = response_with_tool_input({ "joke" => "A joke", "answer" => "An answer" })

      extracted = llm.send(:extract_json_response, resp, model_completion)
      expect(JSON.parse(extracted)).to eq({ "joke" => "A joke", "answer" => "An answer" })
    end

    it "strips unknown root properties before validating an otherwise conforming input" do
      resp = response_with_tool_input({ "joke" => "A joke", "answer" => "An answer", "confidence" => 0.9 })

      extracted = llm.send(:extract_json_response, resp, model_completion)
      expect(JSON.parse(extracted)).to eq({ "joke" => "A joke", "answer" => "An answer" })
    end

    it "preserves unknown root properties when the schema allows them" do
      permissive_schema = schema.merge(additionalProperties: true)
      completion = instance_double(Raif::ModelCompletion, json_response_schema: permissive_schema)
      resp = response_with_tool_input({ "joke" => "A joke", "answer" => "An answer", "confidence" => 0.9 })

      extracted = llm.send(:extract_json_response, resp, completion)
      expect(JSON.parse(extracted)).to eq({ "joke" => "A joke", "answer" => "An answer", "confidence" => 0.9 })
    end

    it "unwraps a payload nested under a json_response key" do
      resp = response_with_tool_input({ "json_response" => { "joke" => "A joke", "answer" => "An answer" } })

      extracted = llm.send(:extract_json_response, resp, model_completion)
      expect(JSON.parse(extracted)).to eq({ "joke" => "A joke", "answer" => "An answer" })
    end

    it "decodes a double-encoded payload (single key whose value is a JSON string)" do
      resp = response_with_tool_input({ "json_response" => { "joke" => "A joke", "answer" => "An answer" }.to_json })

      extracted = llm.send(:extract_json_response, resp, model_completion)
      expect(JSON.parse(extracted)).to eq({ "joke" => "A joke", "answer" => "An answer" })
    end

    it "falls back to text blocks when the tool input carries none of the schema's properties" do
      json_in_text = { "joke" => "From text", "answer" => "Also from text" }.to_json
      resp = response_with_tool_input({ "query" => "forecast" }, text_blocks: [json_in_text])

      extracted = llm.send(:extract_json_response, resp, model_completion)
      expect(JSON.parse(extracted)).to eq({ "joke" => "From text", "answer" => "Also from text" })
    end

    it "returns nil when a stub input has no usable candidate and no text blocks exist" do
      resp = response_with_tool_input({ "query" => {} })

      extracted = llm.send(:extract_json_response, resp, model_completion)
      expect(extracted).to be_nil
    end

    it "passes the input through unchanged when no schema is available" do
      resp = response_with_tool_input({ "query" => "forecast" })

      extracted = llm.send(:extract_json_response, resp, instance_double(Raif::ModelCompletion, json_response_schema: nil))
      expect(JSON.parse(extracted)).to eq({ "query" => "forecast" })
    end
  end
end
