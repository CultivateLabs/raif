# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ModelCompletions::OpenAi, type: :model do
  describe "#prompt_model_for_response!" do
    let(:model_completion) do
      described_class.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "open_ai_gpt_4o",
        model_api_name: "gpt-4o",
        response_format: "text"
      )
    end

    let(:mock_client) { instance_double(OpenAI::Client) }
    let(:response) do
      {
        "choices" => [
          {
            "message" => {
              "content" => "Response content"
            }
          }
        ],
        "usage" => {
          "completion_tokens" => 10,
          "prompt_tokens" => 5,
          "total_tokens" => 15
        }
      }
    end

    before do
      allow(OpenAI::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:chat).and_return(response)
      allow(model_completion).to receive(:save!)
    end

    it "makes a request to the OpenAI API and processes the response" do
      model_completion.prompt_model_for_response!

      expect(model_completion.raw_response).to eq("Response content")
      expect(model_completion.completion_tokens).to eq(10)
      expect(model_completion.prompt_tokens).to eq(5)
      expect(model_completion.total_tokens).to eq(15)
      expect(model_completion).to have_received(:save!)
    end
  end

  describe "#build_chat_parameters" do
    context "with system prompt" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: "You are a helpful assistant",
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          temperature: 0.5,
          response_format: "text"
        )
      end

      it "includes system prompt in the parameters" do
        parameters = model_completion.send(:build_chat_parameters)

        expect(parameters[:model]).to eq("gpt-4o")
        expect(parameters[:temperature]).to eq(0.5)
        expect(parameters[:messages]).to contain_exactly(
          { "role" => "system", "content" => "You are a helpful assistant." },
          { "role" => "user", "content" => "Hello" }
        )
        expect(parameters[:response_format]).to be_nil
      end
    end

    context "with system prompt and JSON response format" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: "You are a helpful assistant",
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          temperature: 0.5,
          response_format: "json"
        )
      end

      it "appends 'Return your response as json.' to the system prompt" do
        allow(model_completion).to receive(:response_format_json?).and_return(true)

        parameters = model_completion.send(:build_chat_parameters)

        expect(parameters[:messages].first["content"]).to eq(
          "You are a helpful assistant. Return your response as json."
        )
      end

      it "ensures the system prompt ends with a period before appending JSON instruction" do
        model_completion.system_prompt = "You are a helpful assistant"
        allow(model_completion).to receive(:response_format_json?).and_return(true)

        parameters = model_completion.send(:build_chat_parameters)

        expect(parameters[:messages].first["content"]).to eq(
          "You are a helpful assistant. Return your response as json."
        )
      end
    end

    context "without system prompt" do
      let(:model_completion) do
        described_class.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          temperature: 0.8,
          response_format: "text"
        )
      end

      it "builds parameters without system prompt" do
        parameters = model_completion.send(:build_chat_parameters)

        expect(parameters[:model]).to eq("gpt-4o")
        expect(parameters[:temperature]).to eq(0.8)
        expect(parameters[:messages]).to eq([{ "role" => "user", "content" => "Hello" }])
        expect(parameters[:response_format]).to be_nil
      end
    end
  end

  describe "#determine_response_format" do
    context "with text response format" do
      let(:model_completion) do
        described_class.new(
          response_format: "text",
          llm_model_key: "open_ai_gpt_4o"
        )
      end

      it "returns nil" do
        expect(model_completion.send(:determine_response_format)).to be_nil
      end
    end

    context "with json response format" do
      let(:model_completion) do
        described_class.new(
          response_format: "json",
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o"
        )
      end

      it "returns the default json_schema format" do
        expect(model_completion.send(:determine_response_format)).to eq({
          "type" => "json_schema",
          "json_schema" => {
            name: "json_response",
            schema: {
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
            },
            strict: true
          }
        })
      end
    end

    context "with json format and source with json_response_schema" do
      let(:schema) do
        {
          "type" => "object",
          "properties" => { "result" => { "type" => "string" } }
        }
      end

      let(:source) do
        double("Source").tap do |s|
          allow(s).to receive(:respond_to?).with(:json_response_schema).and_return(true)
          allow(s).to receive(:json_response_schema).and_return(schema)
        end
      end

      subject(:model_completion) do
        instance = described_class.new(
          response_format: "json",
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o"
        )
        allow(instance).to receive(:source).and_return(source)
        instance
      end

      it "returns json_schema format with schema" do
        result = model_completion.send(:determine_response_format)
        expect(result).to eq({
          "type" => "json_schema",
          "json_schema" => {
            name: "json_response",
            schema: schema,
            strict: true
          }
        })
      end
    end

    context "with json response format and no source with json_response_schema" do
      let(:model_completion) do
        described_class.new(
          response_format: "json",
          llm_model_key: "open_ai_gpt_4o"
        )
      end

      before do
        allow(model_completion).to receive(:response_format_json?).and_return(true)
        allow(model_completion).to receive(:source).and_return(nil)
        allow(model_completion).to receive(:supports_structured_outputs?).and_return(true)
      end

      it "includes the default schema when no source is available" do
        result = model_completion.send(:determine_response_format)

        expect(result["type"]).to eq("json_schema")
        expect(result["json_schema"][:schema]).to eq({
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

      it "includes the default schema when source doesn't respond to json_response_schema" do
        source = double("Source")
        allow(source).to receive(:respond_to?).with(:json_response_schema).and_return(false)
        allow(model_completion).to receive(:source).and_return(source)

        result = model_completion.send(:determine_response_format)

        expect(result["json_schema"][:schema]).to eq({
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

    context "with json response format and supports_structured_outputs? returning false" do
      let(:model_completion) do
        described_class.new(
          response_format: "json",
          llm_model_key: "open_ai_gpt_3_5_turbo",
          model_api_name: "gpt-3.5-turbo"
        )
      end

      before do
        allow(model_completion).to receive(:response_format_json?).and_return(true)
        allow(model_completion).to receive(:supports_structured_outputs?).and_return(false)
      end

      it "returns json_object type when structured outputs are not supported" do
        result = model_completion.send(:determine_response_format)

        expect(result).to eq({ "type" => "json_object" })
      end
    end
  end
end
