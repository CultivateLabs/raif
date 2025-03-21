# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ModelCompletions::BedrockClaude, type: :model do
  describe "#prompt_model_for_response!" do
    let(:model_completion) do
      described_class.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "bedrock_claude_3_5_haiku",
        model_api_name: "anthropic.claude-3-5-haiku-20241022-v1:0",
        response_format: "text",
        max_completion_tokens: 1000
      )
    end

    let(:mock_client) { instance_double(Aws::BedrockRuntime::Client) }
    let(:text_response) do
      text_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock")
      allow(text_content_block).to receive(:respond_to?).with(:text).and_return(true)
      allow(text_content_block).to receive(:text).and_return("Response content")
      allow(text_content_block).to receive(:respond_to?).with(:tool_use).and_return(false)

      instance_double(
        "Aws::BedrockRuntime::Types::ConverseResponse",
        output: instance_double(
          "Aws::BedrockRuntime::Types::ConverseOutput",
          message: instance_double(
            "Aws::BedrockRuntime::Types::Message",
            content: [text_content_block],
            role: "assistant"
          )
        ),
        usage: instance_double(
          "Aws::BedrockRuntime::Types::ConverseUsage",
          input_tokens: 5,
          output_tokens: 10,
          total_tokens: 15
        )
      )
    end

    before do
      allow(Aws::BedrockRuntime::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:converse).and_return(text_response)
      allow(model_completion).to receive(:save!)
      allow(Raif).to receive(:config).and_return(double(aws_bedrock_region: "us-west-2"))
    end

    it "makes a request to the Bedrock API and processes the text response" do
      model_completion.prompt_model_for_response!

      expect(mock_client).to have_received(:converse).with(
        model_id: "anthropic.claude-3-5-haiku-20241022-v1:0",
        inference_config: { max_tokens: 1000 },
        messages: [
          {
            role: "user",
            content: [{ text: "Hello" }]
          }
        ]
      )

      expect(model_completion.raw_response).to eq("Response content")
      expect(model_completion.completion_tokens).to eq(10)
      expect(model_completion.prompt_tokens).to eq(5)
      expect(model_completion.total_tokens).to eq(15)
      expect(model_completion).to have_received(:save!)
    end

    context "with system prompt" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: "You are a helpful assistant",
          llm_model_key: "bedrock_claude_3_5_haiku",
          model_api_name: "anthropic.claude-3-5-haiku-20241022-v1:0",
          response_format: "text",
          max_completion_tokens: 1000
        )
      end

      it "includes system prompt in the request parameters" do
        model_completion.prompt_model_for_response!

        expect(mock_client).to have_received(:converse).with(
          model_id: "anthropic.claude-3-5-haiku-20241022-v1:0",
          inference_config: { max_tokens: 1000 },
          messages: [
            {
              role: "user",
              content: [{ text: "Hello" }]
            }
          ],
          system: [{ text: "You are a helpful assistant" }]
        )
      end
    end

    context "with JSON response format" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "bedrock_claude_3_5_haiku",
          model_api_name: "anthropic.claude-3-5-haiku-20241022-v1:0",
          response_format: "json",
          max_completion_tokens: 1000
        )
      end

      let(:json_response) do
        tool_use_block = instance_double(
          "Aws::BedrockRuntime::Types::ToolUseBlock",
          tool_use_id: "tooluse_123",
          name: "json_response",
          input: { "result" => "Hello World" }
        )

        tool_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock::ToolUse")
        allow(tool_content_block).to receive(:respond_to?).with(:tool_use).and_return(true)
        allow(tool_content_block).to receive(:tool_use).and_return(tool_use_block)
        allow(tool_content_block).to receive(:respond_to?).with(:text).and_return(false)

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: instance_double(
              "Aws::BedrockRuntime::Types::Message",
              content: [tool_content_block],
              role: "assistant"
            )
          ),
          usage: instance_double(
            "Aws::BedrockRuntime::Types::ConverseUsage",
            input_tokens: 10,
            output_tokens: 15,
            total_tokens: 25
          )
        )
      end

      before do
        allow(mock_client).to receive(:converse).and_return(json_response)
      end

      it "configures tools for JSON response and processes the tool response" do
        model_completion.prompt_model_for_response!

        expect(mock_client).to have_received(:converse).with(
          model_id: "anthropic.claude-3-5-haiku-20241022-v1:0",
          inference_config: { max_tokens: 1000 },
          messages: [
            {
              role: "user",
              content: [{ text: "Hello" }]
            }
          ],
          tool_config: {
            tools: [
              {
                tool_spec: {
                  name: "json_response",
                  description: "Generate a structured JSON response based on the provided schema.",
                  input_schema: {
                    json: {
                      type: "object",
                      properties: {
                        response: {
                          type: "string",
                          description: "The complete response text"
                        }
                      },
                      required: ["response"],
                      additionalProperties: false,
                      description: "Return a single text response containing your complete answer"
                    }
                  }
                }
              }
            ],
            tool_choice: {
              tool: {
                name: "json_response"
              }
            }
          }
        )

        expect(model_completion.raw_response).to eq('{"result":"Hello World"}')
        expect(model_completion.completion_tokens).to eq(15)
        expect(model_completion.prompt_tokens).to eq(10)
        expect(model_completion.total_tokens).to eq(25)
      end
    end

    context "with JSON format but no tool response" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "bedrock_claude_3_5_haiku",
          model_api_name: "anthropic.claude-3-5-haiku-20241022-v1:0",
          response_format: "json",
          max_completion_tokens: 1000
        )
      end

      let(:fallback_response) do
        text_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock")
        allow(text_content_block).to receive(:respond_to?).with(:text).and_return(true)
        allow(text_content_block).to receive(:text).and_return("Fallback text response")
        allow(text_content_block).to receive(:respond_to?).with(:tool_use).and_return(false)

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: instance_double(
              "Aws::BedrockRuntime::Types::Message",
              content: [text_content_block],
              role: "assistant"
            )
          ),
          usage: instance_double(
            "Aws::BedrockRuntime::Types::ConverseUsage",
            input_tokens: 8,
            output_tokens: 12,
            total_tokens: 20
          )
        )
      end

      before do
        allow(mock_client).to receive(:converse).and_return(fallback_response)
      end

      it "falls back to text extraction when tool response is missing" do
        model_completion.prompt_model_for_response!

        expect(model_completion.raw_response).to eq("Fallback text response")
        expect(model_completion.completion_tokens).to eq(12)
        expect(model_completion.prompt_tokens).to eq(8)
        expect(model_completion.total_tokens).to eq(20)
      end
    end
  end

  describe "#create_json_tool" do
    context "with default schema" do
      let(:model_completion) do
        described_class.new(
          llm_model_key: "bedrock_claude_3_5_haiku",
          response_format: "json"
        )
      end

      it "creates a tool with default schema" do
        tool = model_completion.send(:format_json_tool, model_completion.send(:create_json_tool))

        expect(tool[:name]).to eq("json_response")
        expect(tool[:description]).to eq("Generate a structured JSON response based on the provided schema.")
        expect(tool[:input_schema]).to eq({
          json: {
            type: "object",
            properties: {
              response: {
                type: "string",
                description: "The complete response text"
              }
            },
            required: ["response"],
            additionalProperties: false,
            description: "Return a single text response containing your complete answer"
          }
        })
      end
    end

    context "with custom schema from source" do
      let(:schema) do
        {
          type: "object",
          properties: { result: { type: "string" } },
          description: "Custom schema description"
        }
      end

      let(:source) do
        double("Source").tap do |s|
          allow(s).to receive(:respond_to?).with(:json_response_schema).and_return(true)
          allow(s).to receive(:json_response_schema).and_return(schema)
        end
      end

      let(:model_completion) do
        instance = described_class.new(
          llm_model_key: "bedrock_claude_3_5_haiku",
          response_format: "json"
        )
        allow(instance).to receive(:source).and_return(source)
        instance
      end

      it "creates a tool with schema from source" do
        tool = model_completion.send(:format_json_tool, model_completion.send(:create_json_tool))

        expect(tool[:name]).to eq("json_response")
        expect(tool[:description]).to eq("Generate a structured JSON response based on the provided schema.")
        expect(tool[:input_schema]).to eq({
          json: schema
        })
      end
    end
  end

  describe "#extract_text_response" do
    let(:model_completion) do
      described_class.new(
        llm_model_key: "bedrock_claude_3_5_haiku"
      )
    end

    context "with valid text response" do
      let(:response_obj) do
        text_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock")
        allow(text_content_block).to receive(:respond_to?).with(:text).and_return(true)
        allow(text_content_block).to receive(:text).and_return("Sample text")

        message = instance_double(
          "Aws::BedrockRuntime::Types::Message",
          content: [text_content_block]
        )

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: message
          )
        )
      end

      it "extracts text from response" do
        result = model_completion.send(:extract_text_response, response_obj)
        expect(result).to eq("Sample text")
      end
    end

    context "with nil or invalid response" do
      let(:empty_response) do
        empty_message = instance_double("Aws::BedrockRuntime::Types::Message", content: [])

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: empty_message
          )
        )
      end

      it "returns nil for empty content" do
        result = model_completion.send(:extract_text_response, empty_response)
        expect(result).to be_nil
      end

      it "returns nil for nil content" do
        nil_message = instance_double("Aws::BedrockRuntime::Types::Message", content: nil)
        nil_response = instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: nil_message
          )
        )

        result = model_completion.send(:extract_text_response, nil_response)
        expect(result).to be_nil
      end
    end
  end

  describe "#extract_json_response" do
    let(:model_completion) do
      described_class.new(
        llm_model_key: "bedrock_claude_3_5_haiku"
      )
    end

    context "with valid tool_use response" do
      let(:response_obj) do
        tool_use_block = instance_double(
          "Aws::BedrockRuntime::Types::ToolUseBlock",
          tool_use_id: "tooluse_123",
          name: "json_response",
          input: { "data" => { "value" => 42, "status" => "success" } }
        )

        tool_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock::ToolUse")
        allow(tool_content_block).to receive(:respond_to?).with(:tool_use).and_return(true)
        allow(tool_content_block).to receive(:tool_use).and_return(tool_use_block)
        allow(tool_content_block).to receive(:respond_to?).with(:text).and_return(false)

        message = instance_double(
          "Aws::BedrockRuntime::Types::Message",
          content: [tool_content_block]
        )

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: message
          )
        )
      end

      it "extracts and formats JSON from tool_use response" do
        result = model_completion.send(:extract_json_response, response_obj)
        parsed_result = JSON.parse(result)
        expect(parsed_result).to eq({ "data" => { "value" => 42, "status" => "success" } })
      end
    end

    context "with tool_use response having incorrect name" do
      let(:response_obj) do
        tool_use_block = instance_double(
          "Aws::BedrockRuntime::Types::ToolUseBlock",
          tool_use_id: "tooluse_456",
          name: "different_tool", # Not "json_response"
          input: { "data" => "should not be returned" }
        )

        tool_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock::ToolUse")
        allow(tool_content_block).to receive(:respond_to?).with(:tool_use).and_return(true)
        allow(tool_content_block).to receive(:tool_use).and_return(tool_use_block)
        allow(tool_content_block).to receive(:respond_to?).with(:text).and_return(false)

        text_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock")
        allow(text_content_block).to receive(:respond_to?).with(:tool_use).and_return(false)
        allow(text_content_block).to receive(:respond_to?).with(:text).and_return(true)
        allow(text_content_block).to receive(:text).and_return("Fallback text")

        message = instance_double(
          "Aws::BedrockRuntime::Types::Message",
          content: [tool_content_block, text_content_block]
        )

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: message
          )
        )
      end

      it "falls back to text extraction when tool name doesn't match" do
        result = model_completion.send(:extract_json_response, response_obj)
        expect(result).to eq("Fallback text")
      end
    end

    context "with no tool_use response" do
      let(:response_obj) do
        text_content_block = instance_double("Aws::BedrockRuntime::Types::ContentBlock")
        allow(text_content_block).to receive(:respond_to?).with(:tool_use).and_return(false)
        allow(text_content_block).to receive(:respond_to?).with(:text).and_return(true)
        allow(text_content_block).to receive(:text).and_return("Just regular text")

        message = instance_double(
          "Aws::BedrockRuntime::Types::Message",
          content: [text_content_block]
        )

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: message
          )
        )
      end

      it "falls back to text extraction when no tool_use is present" do
        result = model_completion.send(:extract_json_response, response_obj)
        expect(result).to eq("Just regular text")
      end
    end

    context "with empty content array" do
      let(:response_obj) do
        message = instance_double(
          "Aws::BedrockRuntime::Types::Message",
          content: []
        )

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: message
          )
        )
      end

      it "falls back to text extraction with empty content" do
        allow(model_completion).to receive(:extract_text_response).and_return(nil)

        result = model_completion.send(:extract_json_response, response_obj)
        expect(result).to be_nil
        expect(model_completion).to have_received(:extract_text_response)
      end
    end

    context "with nil content" do
      let(:response_obj) do
        message = instance_double(
          "Aws::BedrockRuntime::Types::Message",
          content: nil
        )

        instance_double(
          "Aws::BedrockRuntime::Types::ConverseResponse",
          output: instance_double(
            "Aws::BedrockRuntime::Types::ConverseOutput",
            message: message
          )
        )
      end

      it "falls back to text extraction with nil content" do
        allow(model_completion).to receive(:extract_text_response).and_return(nil)

        result = model_completion.send(:extract_json_response, response_obj)
        expect(result).to be_nil
        expect(model_completion).to have_received(:extract_text_response)
      end
    end
  end
end
