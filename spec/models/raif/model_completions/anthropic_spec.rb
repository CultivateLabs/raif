# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ModelCompletions::Anthropic, type: :model do
  describe "#prompt_model_for_response!" do
    let(:model_completion) do
      described_class.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "anthropic_claude_3_opus",
        model_api_name: "claude-3-opus-20240229",
        response_format: "text",
        max_completion_tokens: 1000
      )
    end

    let(:mock_messages) { instance_double("Anthropic::Messages") }
    let(:mock_anthropic) { class_double("Anthropic", messages: mock_messages) }

    let(:text_response) do
      instance_double("Anthropic::Response", body: {
        content: [
          { type: "text", text: "Response content" }
        ],
        usage: {
          input_tokens: 5,
          output_tokens: 10
        }
      })
    end

    before do
      stub_const("::Anthropic", mock_anthropic)
      allow(mock_messages).to receive(:create).and_return(text_response)
      allow(model_completion).to receive(:save!)
    end

    it "makes a request to the Anthropic API and processes the text response" do
      model_completion.prompt_model_for_response!

      expect(mock_messages).to have_received(:create).with(
        model: "claude-3-opus-20240229",
        messages: [{ "role" => "user", "content" => "Hello" }],
        temperature: 0.7,
        max_tokens: 1000
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
          llm_model_key: "anthropic_claude_3_opus",
          model_api_name: "claude-3-opus-20240229",
          response_format: "text",
          max_completion_tokens: 1000
        )
      end

      it "includes system prompt in the request parameters" do
        model_completion.prompt_model_for_response!

        expect(mock_messages).to have_received(:create).with(
          model: "claude-3-opus-20240229",
          messages: [{ "role" => "user", "content" => "Hello" }],
          system: "You are a helpful assistant",
          temperature: 0.7,
          max_tokens: 1000
        )
      end
    end

    context "with JSON response format" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "anthropic_claude_3_opus",
          model_api_name: "claude-3-opus-20240229",
          response_format: "json",
          max_completion_tokens: 1000
        )
      end

      let(:json_response) do
        instance_double("Anthropic::Response", body: {
          content: [
            {
              type: "tool_use",
              name: "json_response",
              input: { "result": "Hello World" }
            }
          ],
          usage: {
            input_tokens: 10,
            output_tokens: 15
          }
        })
      end

      before do
        allow(mock_messages).to receive(:create).and_return(json_response)
      end

      it "configures tools for JSON response and processes the tool response" do
        model_completion.prompt_model_for_response!

        expect(mock_messages).to have_received(:create).with(
          model: "claude-3-opus-20240229",
          messages: [{ "role" => "user", "content" => "Hello" }],
          temperature: 0.7,
          max_tokens: 1000,
          tools: [
            {
              name: "json_response",
              description: "Generate a structured JSON response based on the provided schema.",
              input_schema: {
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
          ]
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
          llm_model_key: "anthropic_claude_3_opus",
          model_api_name: "claude-3-opus-20240229",
          response_format: "json",
          max_completion_tokens: 1000
        )
      end

      let(:fallback_response) do
        instance_double("Anthropic::Response", body: {
          content: [
            { type: "text", text: "Fallback text response" }
          ],
          usage: {
            input_tokens: 8,
            output_tokens: 12
          }
        })
      end

      before do
        allow(mock_messages).to receive(:create).and_return(fallback_response)
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
          llm_model_key: "anthropic_claude_3_opus",
          response_format: "json"
        )
      end

      it "creates a tool with default schema" do
        tool = model_completion.send(:format_json_tool, model_completion.send(:create_json_tool))

        expect(tool[:name]).to eq("json_response")
        expect(tool[:description]).to eq("Generate a structured JSON response based on the provided schema.")
        expect(tool[:input_schema]).to eq({
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
          llm_model_key: "anthropic_claude_3_opus",
          response_format: "json"
        )
        allow(instance).to receive(:source).and_return(source)
        instance
      end

      it "creates a tool with schema from source" do
        tool = model_completion.send(:format_json_tool, model_completion.send(:create_json_tool))

        expect(tool[:name]).to eq("json_response")
        expect(tool[:description]).to eq("Generate a structured JSON response based on the provided schema.")
        expect(tool[:input_schema]).to eq(schema)
      end
    end
  end

  describe "#extract_text_response" do
    let(:model_completion) do
      described_class.new(
        llm_model_key: "anthropic_claude_3_opus"
      )
    end

    context "with valid text response" do
      let(:response) do
        instance_double("Anthropic::Response", body: {
          content: [
            { type: "text", text: "Sample text" }
          ]
        })
      end

      it "extracts text from response" do
        result = model_completion.send(:extract_text_response, response)
        expect(result).to eq("Sample text")
      end
    end

    context "with nil or invalid response" do
      let(:empty_response) do
        instance_double("Anthropic::Response", body: { content: [] })
      end

      it "returns nil for empty content" do
        result = model_completion.send(:extract_text_response, empty_response)
        expect(result).to be_nil
      end

      it "returns nil for nil body" do
        nil_response = instance_double("Anthropic::Response", body: nil)
        result = model_completion.send(:extract_text_response, nil_response)
        expect(result).to be_nil
      end
    end
  end

  describe "#extract_json_response" do
    let(:model_completion) do
      described_class.new(
        llm_model_key: "anthropic_claude_3_opus"
      )
    end

    context "with valid tool_use response" do
      let(:response) do
        instance_double("Anthropic::Response", body: {
          content: [
            {
              type: "tool_use",
              name: "json_response",
              input: { "data" => { "value" => 42, "status" => "success" } }
            }
          ]
        })
      end

      it "extracts and formats JSON from tool_use response" do
        result = model_completion.send(:extract_json_response, response)
        parsed_result = JSON.parse(result)
        expect(parsed_result).to eq({ "data" => { "value" => 42, "status" => "success" } })
      end
    end

    context "with tool_use response having incorrect name" do
      let(:response) do
        instance_double("Anthropic::Response", body: {
          content: [
            {
              type: "tool_use",
              name: "different_tool", # Not "json_response"
              input: { "data" => "should not be returned" }
            },
            { type: "text", text: "Fallback text" }
          ]
        })
      end

      it "falls back to text extraction when tool name doesn't match" do
        allow(model_completion).to receive(:extract_text_response).and_return("Fallback text")

        result = model_completion.send(:extract_json_response, response)
        expect(result).to eq("Fallback text")
        expect(model_completion).to have_received(:extract_text_response)
      end
    end

    context "with no tool_use response" do
      let(:response) do
        instance_double("Anthropic::Response", body: {
          content: [
            { type: "text", text: "Just regular text" }
          ]
        })
      end

      it "falls back to text extraction when no tool_use is present" do
        allow(model_completion).to receive(:extract_text_response).and_return("Just regular text")

        result = model_completion.send(:extract_json_response, response)
        expect(result).to eq("Just regular text")
        expect(model_completion).to have_received(:extract_text_response)
      end
    end

    context "with empty content array" do
      let(:response) do
        instance_double("Anthropic::Response", body: {
          content: []
        })
      end

      it "falls back to text extraction with empty content" do
        allow(model_completion).to receive(:extract_text_response).and_return(nil)

        result = model_completion.send(:extract_json_response, response)
        expect(result).to be_nil
        expect(model_completion).to have_received(:extract_text_response)
      end
    end

    context "with nil body" do
      let(:response) do
        instance_double("Anthropic::Response", body: nil)
      end

      it "falls back to text extraction with nil body" do
        allow(model_completion).to receive(:extract_text_response).and_return(nil)

        result = model_completion.send(:extract_json_response, response)
        expect(result).to be_nil
        expect(model_completion).to have_received(:extract_text_response)
      end
    end
  end
end
