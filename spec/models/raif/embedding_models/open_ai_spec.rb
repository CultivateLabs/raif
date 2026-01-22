# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::EmbeddingModels::OpenAi, type: :model do
  let(:model) { Raif.embedding_model(:open_ai_text_embedding_3_small) }
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
      expect(model.key).to eq(:open_ai_text_embedding_3_small)
      expect(model.api_name).to eq("text-embedding-3-small")
      expect(model.input_token_cost).to eq(0.02 / 1_000_000)
    end
  end

  describe "custom base URL" do
    let(:custom_base_url) { "https://custom-embedding-server.example.com/v1" }
    let(:input) { "Test input" }
    let(:embedding_vector) { Array.new(model.default_output_vector_size) { rand(-1.0..1.0) } }
    let(:response_body) { { "data" => [{ "embedding" => embedding_vector }] } }

    it "uses the configured open_ai_embedding_base_url" do
      allow(Raif.config).to receive(:open_ai_embedding_base_url).and_return(custom_base_url)

      # Create a fresh model instance without memoized connection
      fresh_model = Raif.embedding_model(:open_ai_text_embedding_3_small).dup

      # Verify the connection is built with the custom URL
      connection = fresh_model.send(:connection)
      expect(connection.url_prefix.to_s.chomp("/")).to eq(custom_base_url)
    end
  end

  describe "#generate_embedding!" do
    context "with a string input" do
      let(:input) { "This is a test sentence" }
      let(:embedding_vector) { Array.new(model.default_output_vector_size) { rand(-1.0..1.0) } }
      let(:response_body) { { "data" => [{ "embedding" => embedding_vector }] } }

      it "makes a request to the OpenAI API with the correct parameters" do
        stubs.post("embeddings") do |env|
          expect(JSON.parse(env.body)).to eq({
            "model" => "text-embedding-3-small",
            "input" => input
          })
          [200, { "Content-Type" => "application/json" }, response_body]
        end

        result = model.generate_embedding!(input)
        expect(result).to eq(embedding_vector)
      end

      context "with dimensions parameter" do
        let(:dimensions) { 256 }

        before do
          stubs.post("embeddings") do |env|
            expect(JSON.parse(env.body)).to eq({
              "model" => "text-embedding-3-small",
              "input" => input,
              "dimensions" => dimensions
            })
            [200, { "Content-Type" => "application/json" }, response_body]
          end
        end

        it "includes the dimensions parameter in the request" do
          result = model.generate_embedding!(input, dimensions: dimensions)
          expect(result).to eq(embedding_vector)
        end
      end
    end

    context "with an array input" do
      let(:input) { ["This is sentence one", "This is sentence two"] }
      let(:embedding_vectors) do
        [
          Array.new(model.default_output_vector_size) { rand(-1.0..1.0) },
          Array.new(model.default_output_vector_size) { rand(-1.0..1.0) }
        ]
      end

      let(:response_body) { { "data" => [{ "embedding" => embedding_vectors[0] }, { "embedding" => embedding_vectors[1] }] } }

      before do
        stubs.post("embeddings") do |env|
          expect(JSON.parse(env.body)).to eq({
            "model" => "text-embedding-3-small",
            "input" => input
          })
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the OpenAI API with the array input" do
        result = model.generate_embedding!(input)
        expect(result).to eq(embedding_vectors)
      end
    end

    context "with invalid input type" do
      it "raises an ArgumentError for numeric input" do
        expect { model.generate_embedding!(123) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::OpenAi#generate_embedding! input must be a string or an array of strings"
        )
      end

      it "raises an ArgumentError for hash input" do
        expect { model.generate_embedding!({ text: "test" }) }.to raise_error(
          ArgumentError,
          "Raif::EmbeddingModels::OpenAi#generate_embedding! input must be a string or an array of strings"
        )
      end
    end

    context "when the API returns a 400-level error" do
      let(:input) { "Test input" }
      let(:error_response_body) do
        <<~JSON
          {
            "error": {
              "message": "Rate limited",
              "type": "rate_limit_error",
              "code": 429
            }
          }
        JSON
      end

      before do
        stubs.post("embeddings") do |_env|
          raise Faraday::ClientError.new(
            "Rate limited",
            { status: 429, body: error_response_body }
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
      let(:error_response_body) do
        <<~JSON
          {
            "error": {
              "message": "Internal server error",
              "code": 500
            }
          }
        JSON
      end

      before do
        stubs.post("embeddings") do |_env|
          raise Faraday::ServerError.new(
            "Internal server error",
            { status: 500, body: error_response_body }
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
