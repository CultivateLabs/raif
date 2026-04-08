# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::XAi, type: :model do
  it_behaves_like "an LLM that uses OpenAI's Completions API message formatting"
  it_behaves_like "an LLM that uses OpenAI's Completions API tool formatting"

  let(:llm){ Raif.llm(:x_ai_grok_3_beta) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
  end

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the xAI API and processes the text response", vcr: { cassette_name: "x_ai/text_response" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")

        expect(model_completion.raw_response).to be_present
        expect(model_completion.completion_tokens).to be > 0
        expect(model_completion.prompt_tokens).to be > 0
        expect(model_completion.total_tokens).to be > 0
        expect(model_completion.llm_model_key).to eq("x_ai_grok_3_beta")
        expect(model_completion.model_api_name).to eq("grok-3-beta")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
      end
    end

    context "when the response format is json" do
      it "makes a request to the xAI API and processes the json response", vcr: { cassette_name: "x_ai/json_response" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you tell me a joke? Respond in JSON format with joke and answer keys." }],
          response_format: :json
        )

        expect(model_completion.raw_response).to be_present
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.parsed_response).to be_a(Hash)
      end
    end

    context "when using developer-managed tools" do
      it "extracts tool calls correctly", vcr: { cassette_name: "x_ai/developer_managed_fetch_url" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_tool_calls).to be_an(Array)
        expect(model_completion.response_tool_calls.first["name"]).to eq("fetch_url")
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

      it "streams a text response correctly", vcr: { cassette_name: "x_ai/streaming_text" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Hello" }]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to be_present
        expect(model_completion.completion_tokens).to be > 0
        expect(model_completion.prompt_tokens).to be > 0
        expect(model_completion.total_tokens).to be > 0
        expect(model_completion).to be_persisted
        expect(model_completion.llm_model_key).to eq("x_ai_grok_3_beta")
        expect(model_completion.model_api_name).to eq("grok-3-beta")
        expect(deltas).not_to be_empty
      end
    end

    context "when the API returns a nil response body" do
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
        allow(llm).to receive(:connection).and_return(test_connection)

        stubs.post("chat/completions") do |_env|
          [200, { "Content-Type" => "application/json" }, nil]
        end
      end

      it "raises BlankResponseError so the task is marked as failed" do
        expect do
          llm.chat(
            messages: [{ role: "user", content: "Hello" }],
            response_format: :json
          )
        end.to raise_error(Raif::Errors::BlankResponseError)
      end
    end

    context "errors" do
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
        allow(llm).to receive(:connection).and_return(test_connection)
      end

      context "when the API returns a 400-level error" do
        before do
          stubs.post("chat/completions") do |_env|
            raise Faraday::ClientError.new(
              "Rate limited",
              { status: 429, body: '{"error":{"code":429,"message":"Rate limited"}}' }
            )
          end

          allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
        end

        it "raises a Faraday::ClientError" do
          expect do
            llm.chat(message: "Hello")
          end.to raise_error(Faraday::ClientError)
        end
      end

      context "when the API returns a 500-level error" do
        before do
          stubs.post("chat/completions") do |_env|
            raise Faraday::ServerError.new(
              "Internal server error",
              { status: 500, body: '{"error":{"code":500,"message":"Internal server error"}}' }
            )
          end

          allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
        end

        it "raises a ServerError" do
          expect do
            llm.chat(message: "Hello")
          end.to raise_error(Faraday::ServerError)
        end
      end
    end
  end

  describe "#build_request_parameters" do
    context "with system prompt" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: "You are a helpful assistant.",
          llm_model_key: "x_ai_grok_3_beta",
          model_api_name: "grok-3-beta",
          temperature: 0.5
        )
      end

      it "builds the correct parameters with system prompt" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:model]).to eq("grok-3-beta")
        expect(params[:temperature]).to eq(0.5)
        expect(params[:messages].first["role"]).to eq("system")
        expect(params[:messages].first["content"]).to eq("You are a helpful assistant.")
        expect(params[:messages].last["role"]).to eq("user")
        expect(params[:messages].last["content"]).to eq("Hello")
        expect(params[:stream]).to eq(nil)
      end
    end

    context "with model tools" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "I need information" }],
          llm_model_key: "x_ai_grok_3_beta",
          model_api_name: "grok-3-beta",
          available_model_tools: ["Raif::TestModelTool"]
        )
      end

      it "includes tools in the request parameters" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:tools]).to be_an(Array)
        expect(params[:tools].length).to eq(1)

        tool = params[:tools].first
        expect(tool[:type]).to eq("function")
        expect(tool[:function][:name]).to eq(Raif::TestModelTool.tool_name)
        expect(tool[:function][:description]).to eq("Mock Tool Description")
        expect(tool[:function][:parameters]).to eq(Raif::TestModelTool.tool_arguments_schema)
      end
    end
  end

  describe "#extract_response_tool_calls" do
    context "when there are tool calls in the response" do
      let(:response_json) do
        {
          "choices" => [
            {
              "message" => {
                "tool_calls" => [
                  {
                    "id" => "call_123",
                    "type" => "function",
                    "function" => {
                      "name" => "test_tool",
                      "arguments" => "{\"query\":\"test query\"}"
                    }
                  }
                ]
              }
            }
          ]
        }
      end

      it "extracts tool calls correctly" do
        tool_calls = llm.send(:extract_response_tool_calls, response_json)

        expect(tool_calls).to be_an(Array)
        expect(tool_calls.length).to eq(1)

        tool_call = tool_calls.first
        expect(tool_call["name"]).to eq("test_tool")
        expect(tool_call["arguments"]).to eq({ "query" => "test query" })
      end
    end

    context "when there are no tool calls in the response" do
      let(:response_json) do
        {
          "choices" => [
            {
              "message" => {
                "content" => "Response content"
              }
            }
          ]
        }
      end

      it "returns nil" do
        tool_calls = llm.send(:extract_response_tool_calls, response_json)
        expect(tool_calls).to eq(nil)
      end
    end
  end

  describe "#build_forced_tool_choice" do
    it "returns the correct format for forcing a specific tool" do
      result = llm.build_forced_tool_choice("agent_final_answer")
      expect(result).to eq({ "type" => "function", "function" => { "name" => "agent_final_answer" } })
    end
  end
end
