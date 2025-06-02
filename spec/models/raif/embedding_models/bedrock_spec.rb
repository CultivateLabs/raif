# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::EmbeddingModels::Bedrock, type: :model do
  let(:model) { Raif.embedding_model(:bedrock_titan_embed_text_v2) }
  let(:client) { Aws::BedrockRuntime::Client.new(stub_responses: true) }
  let(:mock_response) { double("MockResponse") }

  before do
    allow(model).to receive(:bedrock_client).and_return(client)
  end

  describe "initialization" do
    it "sets the correct attributes" do
      expect(model.key).to eq(:bedrock_titan_embed_text_v2)
      expect(model.api_name).to eq("amazon.titan-embed-text-v2:0")
      expect(model.input_token_cost).to eq(0.01 / 1_000_000)
    end
  end

  describe "#generate_embedding!" do
    context "with a string input" do
      let(:input) { "This is a test sentence" }
      let(:embedding_vector) { Array.new(model.default_output_vector_size) { rand(-1.0..1.0) } }
      let(:response_body) { { "embedding" => embedding_vector } }

      before do
        # Create a StringIO object with the JSON response
        response_io = StringIO.new(response_body.to_json)

        # Create a mock response object with a body attribute that has a read method
        mock_body = double("MockBody")
        allow(mock_body).to receive(:read).and_return(response_io.read)

        # Set up the client to return our mock response
        allow(client).to receive(:invoke_model).and_return(double("Response", body: mock_body))
      end

      it "makes a request to the Bedrock API with the correct parameters" do
        expected_params = {
          model_id: "amazon.titan-embed-text-v2:0",
          body: { inputText: input }.to_json
        }

        expect(client).to receive(:invoke_model).with(hash_including(expected_params))

        result = model.generate_embedding!(input)
        expect(result).to eq(embedding_vector)
      end

      context "with dimensions parameter" do
        let(:dimensions) { 256 }

        it "includes the dimensions parameter in the request" do
          expected_params = {
            model_id: "amazon.titan-embed-text-v2:0",
            body: { inputText: input, dimensions: dimensions }.to_json
          }

          expect(client).to receive(:invoke_model).with(hash_including(expected_params))

          model.generate_embedding!(input, dimensions: dimensions)
        end
      end
    end

    context "with invalid input type" do
      it "raises an ArgumentError for numeric input" do
        expect { model.generate_embedding!(123) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::Bedrock#generate_embedding! input must be a string"
        )
      end

      it "raises an ArgumentError for array input" do
        expect { model.generate_embedding!(["test1", "test2"]) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::Bedrock#generate_embedding! input must be a string"
        )
      end

      it "raises an ArgumentError for hash input" do
        expect { model.generate_embedding!({ text: "test" }) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::Bedrock#generate_embedding! input must be a string"
        )
      end
    end

    context "when the API returns an error" do
      let(:input) { "Test input" }
      let(:error_message) { "Rate limit exceeded" }

      before do
        allow(client).to receive(:invoke_model).and_raise(
          Aws::BedrockRuntime::Errors::ServiceError.new(nil, error_message)
        )
      end

      it "raises an error with the AWS error message" do
        expect do
          model.generate_embedding!(input)
        end.to raise_error("Bedrock API error: Rate limit exceeded")
      end
    end
  end
end
