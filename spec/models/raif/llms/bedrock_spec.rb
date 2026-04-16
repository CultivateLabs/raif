# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Bedrock, type: :model do
  let(:llm){ Raif.llm(:bedrock_claude_3_5_sonnet) }

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

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the Bedrock API and processes the text response", vcr: { cassette_name: "bedrock/text_response" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")
        expect(model_completion.raw_response).to eq("Hi! How can I help you today?")
        expect(model_completion.completion_tokens).to eq(12)
        expect(model_completion.prompt_tokens).to eq(14)
        expect(model_completion.total_tokens).to eq(26)
        expect(model_completion.llm_model_key).to eq("bedrock_claude_3_5_sonnet")
        expect(model_completion.model_api_name).to eq("us.anthropic.claude-3-5-sonnet-20241022-v2:0")
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
        expect(model_completion.llm_model_key).to eq("bedrock_claude_3_5_sonnet")
        expect(model_completion.model_api_name).to eq("us.anthropic.claude-3-5-sonnet-20241022-v2:0")
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
        llm_model_key: "bedrock_claude_3_5_sonnet",
        model_api_name: "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
      )
    end

    it "builds the correct parameters" do
      parameters = llm.send(:build_request_parameters, model_completion)
      expect(parameters[:model_id]).to eq("us.anthropic.claude-3-5-sonnet-20241022-v2:0")
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
  end

  describe "#resolve_model_api_name" do
    it "prefixes non-gpt-oss model ids when a prefix is configured" do
      allow(Raif.config).to receive(:aws_bedrock_model_name_prefix).and_return("us")

      resolved = llm.send(:resolve_model_api_name, "anthropic.claude-3-5-sonnet-20241022-v2:0")
      expect(resolved).to eq("us.anthropic.claude-3-5-sonnet-20241022-v2:0")
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

      resolved = llm.send(:resolve_model_api_name, "us.anthropic.claude-3-5-sonnet-20241022-v2:0")
      expect(resolved).to eq("us.anthropic.claude-3-5-sonnet-20241022-v2:0")
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
      allow(llm).to receive(:sleep)
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
    it "includes AWS SDK exceptions in addition to the default retriable exceptions" do
      exceptions = llm.send(:retriable_exceptions)
      expect(exceptions).to include(Aws::BedrockRuntime::Errors::ServiceError)
      expect(exceptions).to include(Seahorse::Client::NetworkingError)
      Raif.config.llm_request_retriable_exceptions.each do |exception|
        expect(exceptions).to include(exception)
      end
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
        llm_model_key: "bedrock_claude_3_5_sonnet",
        model_api_name: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
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
        llm_model_key: "bedrock_claude_3_5_sonnet",
        model_api_name: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
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
end
