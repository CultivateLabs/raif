# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::EmbeddingModels::Google, type: :model do
  let(:model) { Raif.embedding_model(:google_gemini_embedding_2) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new do |builder|
      builder.adapter :test, stubs
      builder.request :json
      builder.response :json
      builder.response :raise_error
    end
  end

  before do
    allow(model).to receive(:connection).and_return(test_connection)
  end

  describe "initialization" do
    it "sets the correct attributes" do
      expect(model.key).to eq(:google_gemini_embedding_2)
      expect(model.api_name).to eq("gemini-embedding-2-preview")
      expect(model.input_token_cost).to eq(0.20 / 1_000_000)
      expect(model.default_output_vector_size).to eq(3072)
    end
  end

  describe "#generate_embedding!" do
    context "with a string input" do
      let(:input) { "This is a test sentence" }
      let(:embedding_vector) { Array.new(model.default_output_vector_size) { rand(-1.0..1.0) } }
      let(:response_body) { { "embedding" => { "values" => embedding_vector } } }

      it "makes a request to the Google API with the correct parameters" do
        stubs.post("models/gemini-embedding-2-preview:embedContent") do |env|
          expect(JSON.parse(env.body)).to eq({
            "content" => {
              "parts" => [{ "text" => input }]
            }
          })
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = model.generate_embedding!(input)
        expect(result).to eq(embedding_vector)
      end

      context "with dimensions parameter" do
        let(:dimensions) { 768 }

        before do
          stubs.post("models/gemini-embedding-2-preview:embedContent") do |env|
            expect(JSON.parse(env.body)).to eq({
              "content" => {
                "parts" => [{ "text" => input }]
              },
              "outputDimensionality" => dimensions
            })
            [200, { "Content-Type" => "application/json" }, response_body]
          end
        end

        it "includes the outputDimensionality parameter in the request" do
          result = model.generate_embedding!(input, dimensions: dimensions)
          expect(result).to eq(embedding_vector)
        end
      end
    end

    context "with invalid input type" do
      it "raises an ArgumentError for numeric input" do
        expect { model.generate_embedding!(123) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::Google#generate_embedding! input must be a string"
        )
      end

      it "raises an ArgumentError for array input" do
        expect { model.generate_embedding!(["test1", "test2"]) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::Google#generate_embedding! input must be a string"
        )
      end

      it "raises an ArgumentError for hash input" do
        expect { model.generate_embedding!({ text: "test" }) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::Google#generate_embedding! input must be a string"
        )
      end
    end

    context "when the API returns a 400-level error" do
      let(:input) { "Test input" }

      before do
        stubs.post("models/gemini-embedding-2-preview:embedContent") do |_env|
          raise Faraday::ClientError.new(
            "Rate limited",
            { status: 429, body: '{"error": {"message": "Rate limited"}}' }
          )
        end

        allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
      end

      it "raises a Faraday::ClientError" do
        expect do
          model.generate_embedding!(input)
        end.to raise_error(Faraday::ClientError)
      end
    end

    context "when the API returns a 500-level error" do
      let(:input) { "Test input" }

      before do
        stubs.post("models/gemini-embedding-2-preview:embedContent") do |_env|
          raise Faraday::ServerError.new(
            "Internal server error",
            { status: 500, body: '{"error": {"message": "Internal server error"}}' }
          )
        end

        allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
      end

      it "raises a Faraday::ServerError" do
        expect do
          model.generate_embedding!(input)
        end.to raise_error(Faraday::ServerError)
      end
    end
  end
end
