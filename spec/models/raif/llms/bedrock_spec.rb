# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Bedrock, type: :model do
  let(:llm){ Raif.llm(:bedrock_claude_3_5_sonnet) }
  let(:client) { Aws::BedrockRuntime::Client.new(stub_responses: true) }

  before do
    allow(llm).to receive(:bedrock_client).and_return(client)
  end

  describe "#chat" do
    context "when the response format is text" do
      before do
        client.stub_responses(:converse, {
          output: {
            message: {
              role: "assistant",
              content: [{ text: "Response content" }]
            }
          },
          stop_reason: "end_turn",
          usage: { input_tokens: 8, output_tokens: 13, total_tokens: 21 },
          metrics: { latency_ms: 540 }
        })
      end

      it "makes a request to the Bedrock API and processes the text response" do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")
        expect(model_completion.raw_response).to eq("Response content")
        expect(model_completion.completion_tokens).to eq(13)
        expect(model_completion.prompt_tokens).to eq(8)
        expect(model_completion.total_tokens).to eq(21)
        expect(model_completion.llm_model_key).to eq("bedrock_claude_3_5_sonnet")
        expect(model_completion.model_api_name).to eq("us.anthropic.claude-3-5-sonnet-20241022-v2:0")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
        expect(model_completion.messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello" }] }])
        expect(model_completion.response_array).to eq([{ "text" => "Response content" }])
      end
    end

    context "when using developer-managed tools" do
      before do
        client.stub_responses(:converse, {
          output: {
            message: {
              role: "assistant",
              content: [
                { text: "I'll fetch the content of the Wall Street Journal homepage for you." },
                {
                  tool_use: {
                    tool_use_id: "call_RNzLf3E3dsfjh98mRsQYabd1mSB",
                    name: "fetch_url",
                    input: { "url" => "https://www.wsj.com" }
                  }
                }
              ]
            }
          },
          stop_reason: "tool_use",
          usage: { input_tokens: 364, output_tokens: 75, total_tokens: 439 },
          metrics: { latency_ms: 540 }
        })
      end

      it "extracts tool calls correctly" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.raw_response).to eq("I'll fetch the content of the Wall Street Journal homepage for you.")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([
          { "text" => "I'll fetch the content of the Wall Street Journal homepage for you." },
          {
            "tool_use" =>
              {
                "tool_use_id" => "call_RNzLf3E3dsfjh98mRsQYabd1mSB",
                "name" => "fetch_url",
                "input" => { "url" => "https://www.wsj.com" }
              }
          }
        ])

        expect(model_completion.response_tool_calls).to eq([{
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
  end
end
