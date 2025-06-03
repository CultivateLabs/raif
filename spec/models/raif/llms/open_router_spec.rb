# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::OpenRouter, type: :model do
  it_behaves_like "an LLM that uses OpenAI's Completions API message formatting"
  it_behaves_like "an LLM that uses OpenAI's Completions API tool formatting"

  let(:llm){ Raif.llm(:open_router_claude_3_7_sonnet) }
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

  describe "#chat" do
    context "when the response format is text" do
      let(:response_body) do
        {
          "choices" => [{ "message" => { "content" => "Response content" } }],
          "usage" => { "completion_tokens" => 10, "prompt_tokens" => 5, "total_tokens" => 15 }
        }
      end

      before do
        stubs.post("chat/completions") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the OpenRouter API and processes the text response" do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")

        expect(model_completion.raw_response).to eq("Response content")
        expect(model_completion.completion_tokens).to eq(10)
        expect(model_completion.prompt_tokens).to eq(5)
        expect(model_completion.total_tokens).to eq(15)
        expect(model_completion.llm_model_key).to eq("open_router_claude_3_7_sonnet")
        expect(model_completion.model_api_name).to eq("anthropic/claude-3.7-sonnet")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
        expect(model_completion.response_array).to eq([{ "message" => { "content" => "Response content" } }])
      end
    end

    context "when the response format is json" do
      let(:response_body) do
        {
          "id" => "gen-1748455370-i2bE4HRhXR02lltZZKFD",
          "provider" => "Google",
          "model" => "anthropic/claude-3.7-sonnet",
          "object" => "chat.completion",
          "created" => 1748455370,
          "choices" => [{
            "logprobs" => nil,
            "finish_reason" => "stop",
            "native_finish_reason" => "stop",
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "```json\n{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}\n```",
              "refusal" => nil,
              "reasoning" => nil
            }
          }],
          "usage" => { "prompt_tokens" => 74, "completion_tokens" => 31, "total_tokens" => 105 }
        }
      end

      before do
        stubs.post("chat/completions") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the OpenRouter API and processes the json response" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you you tell me a joke? Respond in JSON format." }],
          response_format: :json
        )

        expect(model_completion.raw_response).to eq("```json\n{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}\n```") # rubocop:disable Layout/LineLength
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.parsed_response).to eq({ "joke" => "Why don't scientists trust atoms? Because they make up everything!" })
        expect(model_completion.completion_tokens).to eq(31)
        expect(model_completion.prompt_tokens).to eq(74)
        expect(model_completion.response_array).to eq([{
          "logprobs" => nil,
          "finish_reason" => "stop",
          "native_finish_reason" => "stop",
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" => "```json\n{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}\n```",
            "refusal" => nil,
            "reasoning" => nil
          }
        }])
      end
    end

    context "when using developer-managed tools" do
      let(:response_body) do
        json_file = File.read(Raif::Engine.root.join("spec/fixtures/llm_responses/open_router/developer_managed_fetch_url.json"))
        JSON.parse(json_file)
      end

      before do
        stubs.post("chat/completions") do |env|
          body = JSON.parse(env.body)

          expect(body["tools"]).to eq([{
            "type" => "function",
            "function" => {
              "name" => "fetch_url",
              "description" => "Fetch a URL and return the page content as markdown",
              "parameters" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => { "url" => { "type" => "string", "description" => "The URL to fetch content from" } },
                "required" => ["url"]
              }
            }
          }])

          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "extracts tool calls correctly" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.raw_response).to eq("I can help you check what's on the homepage of The Wall Street Journal (WSJ) website today. Let me fetch that for you.") # rubocop:disable Layout/LineLength
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([{
          "logprobs" => nil,
          "finish_reason" => "tool_calls",
          "native_finish_reason" => "tool_calls",
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" =>
           "I can help you check what's on the homepage of The Wall Street Journal (WSJ) website today. Let me fetch that for you.",
            "refusal" => nil,
            "reasoning" => nil,
            "tool_calls" => [{
              "id" => "toolu_vrtx_014TAQp4ndsg8yZS2my3wXvWK",
              "index" => 0,
              "type" => "function",
              "function" => { "name" => "fetch_url", "arguments" => "{\"url\": \"https://www.wsj.com\"}" }
            }]
          }
        }])

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

    context "when the API returns a 400-level error" do
      let(:error_response_body) do
        <<~JSON
          {
            "error": {
              "code": 429,
              "message": "Rate limited",
              "metadata": ""
            }
          }
        JSON
      end

      before do
        stubs.post("chat/completions") do |_env|
          raise Faraday::ClientError.new(
            "Rate limited",
            { status: 429, body: error_response_body }
          )
        end

        allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
      end

      it "raises a Faraday::ClientError with the error message" do
        expect do
          llm.chat(message: "Hello")
        end.to raise_error(Faraday::ClientError)
      end
    end

    context "when the API returns a 500-level error" do
      let(:error_response_body) do
        <<~JSON
          {
            "error": {
              "code": 500,
              "message": "Internal server error",
              "metadata": ""
            }
          }
        JSON
      end

      before do
        stubs.post("chat/completions") do |_env|
          raise Faraday::ServerError.new(
            "Internal server error",
            { status: 500, body: error_response_body }
          )
        end

        allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
      end

      it "raises a ServerError with the error message" do
        expect do
          llm.chat(message: "Hello")
        end.to raise_error(Faraday::ServerError)
      end
    end
  end

  describe "#build_request_parameters" do
    context "with system prompt" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: "You are a helpful assistant.",
          llm_model_key: "open_router_claude_3_7_sonnet",
          model_api_name: "anthropic/claude-3.7-sonnet",
          temperature: 0.5
        )
      end

      it "builds the correct parameters with system prompt" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:model]).to eq("anthropic/claude-3.7-sonnet")
        expect(params[:temperature]).to eq(0.5)
        expect(params[:messages].first["role"]).to eq("system")
        expect(params[:messages].first["content"]).to eq("You are a helpful assistant.")
        expect(params[:messages].last["role"]).to eq("user")
        expect(params[:messages].last["content"]).to eq("Hello")
        expect(params[:stream]).to eq(false)
      end
    end

    context "with model tools" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "I need information" }],
          llm_model_key: "open_router_claude_3_7_sonnet",
          model_api_name: "anthropic/claude-3.7-sonnet",
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
end
