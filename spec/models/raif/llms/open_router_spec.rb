# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::OpenRouter, type: :model do
  it_behaves_like "an LLM that uses OpenAI's Completions API message formatting"
  it_behaves_like "an LLM that uses OpenAI's Completions API tool formatting"

  let(:llm){ Raif.llm(:open_router_llama_3_1_8b_instruct) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
  end

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the OpenRouter API and processes the text response", vcr: { cassette_name: "open_router/text_response" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")

        expect(model_completion.raw_response).to eq("Hello! How can I assist you today?")
        expect(model_completion.completion_tokens).to eq(9)
        expect(model_completion.prompt_tokens).to eq(22)
        expect(model_completion.total_tokens).to eq(31)
        expect(model_completion.llm_model_key).to eq("open_router_llama_3_1_8b_instruct")
        expect(model_completion.model_api_name).to eq("meta-llama/llama-3.1-8b-instruct")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
        expect(model_completion.response_array).to eq([{
          "finish_reason" => "stop",
          "index" => 0,
          "logprobs" => nil,
          "message" => {
            "content" => "Hello! How can I assist you today?",
            "reasoning" => nil,
            "refusal" => nil,
            "role" => "assistant"
          },
          "native_finish_reason" => "stop"
        }])
      end
    end

    context "when the response format is json and model does not use json_response tool" do
      it "makes a request to the OpenRouter API and processes the json response", vcr: { cassette_name: "open_router/json_response" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you you tell me a joke? Respond in JSON format. Include nothing outside of the JSON." }],
          response_format: :json
        )

        expect(model_completion.raw_response).to eq("{\n  \"joke\": \"Why don't scientists trust atoms?\",\n  \"answer\": \"Because they make up everything!\"\n}") # rubocop:disable Layout/LineLength
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.parsed_response).to eq({ "joke" => "Why don't scientists trust atoms?", "answer" => "Because they make up everything!" }) # rubocop:disable Layout/LineLength
        expect(model_completion.completion_tokens).to eq(27)
        expect(model_completion.prompt_tokens).to eq(55)
        expect(model_completion.response_array).to eq([{
          "logprobs" => nil,
          "finish_reason" => "stop",
          "native_finish_reason" => "stop",
          "index" => 0,
          "message" =>
         {
           "role" => "assistant",
           "content" => "{\n  \"joke\": \"Why don't scientists trust atoms?\",\n  \"answer\": \"Because they make up everything!\"\n}",
           "refusal" => nil,
           "reasoning" => nil
         }
        }])
      end
    end

    context "when the response format is JSON and model uses json_response tool" do
      let(:test_task) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      context "when using open_router_llama_4_maverick" do
        let(:llm){ Raif.llm(:open_router_llama_4_maverick) }

        it "extracts JSON response from json_response tool call", vcr: { cassette_name: "open_router/format_json_with_tool_llama4_maverick" } do
          model_completion = llm.chat(
            messages: [{
              role: "user",
              content: "Please give me a JSON object with a joke and answer. Don't include any other text in your response. Use the json_response tool to provide your response." # rubocop:disable Layout/LineLength
            }],
            response_format: :json,
            source: test_task
          )

          expect(model_completion.parsed_response).to eq({
            "joke" => "Why don't scientists trust atoms?",
            "answer" => "Because they make up everything."
          })

          expect(model_completion.raw_response).to eq("{\"joke\": \"Why don't scientists trust atoms?\", \"answer\": \"Because they make up everything.\"}") # rubocop:disable Layout/LineLength
          expect(model_completion.response_tool_calls).to eq([{
            "provider_tool_call_id" => "chatcmpl-abc123-9807d1c0536c4e46903bc13b4a820170",
            "name" => "json_response",
            "arguments" => {
              "joke" => "Why don't scientists trust atoms?",
              "answer" => "Because they make up everything."
            }
          }])
          expect(model_completion.completion_tokens).to eq(33)
          expect(model_completion.prompt_tokens).to eq(217)
          expect(model_completion.total_tokens).to eq(250)
          expect(model_completion.response_format).to eq("json")
          expect(model_completion.response_id).to eq("gen-abc123-Xzzn8cgXV0Pew0ckjxYE")
          expect(model_completion.response_array).to eq([{
            "logprobs" => nil,
            "finish_reason" => "tool_calls",
            "native_finish_reason" => "tool_calls",
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "",
              "refusal" => nil,
              "reasoning" => nil,
              "tool_calls" => [{
                "id" => "chatcmpl-abc123-9807d1c0536c4e46903bc13b4a820170",
                "type" => "function",
                "index" => 0,
                "function" => {
                  "name" => "json_response",
                  "arguments" => "{\"joke\": \"Why don't scientists trust atoms?\", \"answer\": \"Because they make up everything.\"}"
                }
              }]
            }
          }])
        end
      end

      context "when using open_router_open_ai_gpt_oss_20b" do
        let(:llm){ Raif.llm(:open_router_open_ai_gpt_oss_20b) }

        it "extracts JSON response from json_response tool call", vcr: { cassette_name: "open_router/format_json_with_tool_gpt_oss_20b" } do
          model_completion = llm.chat(
            messages: [{
              role: "user",
              content: "Please give me a JSON object with a joke and answer. Don't include any other text in your response. Use the json_response tool to provide your response." # rubocop:disable Layout/LineLength
            }],
            response_format: :json,
            source: test_task
          )

          expect(model_completion.parsed_response).to eq({
            "answer" => "What do you call a fish with no eyes? Fsh.",
            "joke" => "Why did the scarecrow win an award? Because he was outstanding in his field!"
          })

          expect(model_completion.raw_response).to eq("{\"answer\":\"What do you call a fish with no eyes? Fsh.\",\"joke\":\"Why did the scarecrow win an award? Because he was outstanding in his field!\"}") # rubocop:disable Layout/LineLength
          expect(model_completion.response_tool_calls).to eq([{
            "provider_tool_call_id" => "fc_abc123-444c-4c46-8e42-838348740c0b",
            "name" => "json_response",
            "arguments" => {
              "joke" => "Why did the scarecrow win an award? Because he was outstanding in his field!",
              "answer" => "What do you call a fish with no eyes? Fsh."
            }
          }])
          expect(model_completion.completion_tokens).to eq(71)
          expect(model_completion.prompt_tokens).to eq(160)
          expect(model_completion.total_tokens).to eq(231)
          expect(model_completion.response_format).to eq("json")
          expect(model_completion.response_id).to eq("gen-abc123-WQ3Wm9AMMlb2WZU5qCQk")
          expect(model_completion.response_array).to eq([{
            "logprobs" => nil,
            "finish_reason" => "tool_calls",
            "native_finish_reason" => "stop",
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "",
              "refusal" => nil,
              "reasoning" => "We must use the json_response tool. So we need to call it.",
              "reasoning_details" => [
                {
                  "format" => "unknown",
                  "index" => 0,
                  "text" => "We must use the json_response tool. So we need to call it.",
                  "type" => "reasoning.text"
                }
              ],
              "tool_calls" => [{
                "id" => "fc_abc123-444c-4c46-8e42-838348740c0b",
                "type" => "function",
                "index" => 0,
                "function" => {
                  "name" => "json_response",
                  "arguments" => "{\"answer\":\"What do you call a fish with no eyes? Fsh.\",\"joke\":\"Why did the scarecrow win an award? Because he was outstanding in his field!\"}" # rubocop:disable Layout/LineLength
                }
              }]
            }
          }])
        end
      end
    end

    context "when using developer-managed tools" do
      it "extracts tool calls correctly", vcr: { cassette_name: "open_router/developer_managed_fetch_url" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.raw_response).to eq("")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([{
          "logprobs" => nil,
          "finish_reason" => "stop",
          "native_finish_reason" => "stop",
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" => "",
            "refusal" => nil,
            "reasoning" => nil,
            "tool_calls" => [{
              "index" => 0,
              "id" => "call_abc123",
              "function" => { "arguments" => "{\"url\": \"https://www.wsj.com\"}", "name" => "fetch_url" },
              "type" => "function"
            }]
          }
        }])

        expect(model_completion.response_tool_calls).to eq([{
          "provider_tool_call_id" => "call_abc123",
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

      it "streams a text response correctly", vcr: { cassette_name: "open_router/streaming_text" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Hello" }]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("Hello! How can I help you today?")
        expect(model_completion.completion_tokens).to eq(9)
        expect(model_completion.prompt_tokens).to eq(11)
        expect(model_completion.total_tokens).to eq(20)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{
          "content" => [{
            "text" => "Hello",
            "type" => "text"
          }],
          "role" => "user"
        }])
        expect(model_completion.llm_model_key).to eq("open_router_llama_3_1_8b_instruct")
        expect(model_completion.model_api_name).to eq("meta-llama/llama-3.1-8b-instruct")

        expect(deltas).to eq(["Hello! How", " can I help", " you today", "?"])
      end

      it "streams a json response correctly", vcr: { cassette_name: "open_router/streaming_json" } do
        system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object." # rubocop:disable Layout/LineLength

        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you you tell me a joke? Respond in json." }],
          system_prompt: system_prompt,
          response_format: :json
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}")
        expect(model_completion.parsed_response).to eq({ "joke" => "Why don't scientists trust atoms? Because they make up everything!" })
        expect(model_completion.completion_tokens).to eq(21)
        expect(model_completion.prompt_tokens).to eq(70)
        expect(model_completion.total_tokens).to eq(91)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([
          {
            "role" => "system",
            "content" => "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object." # rubocop:disable Layout/LineLength
          },
          {
            "role" => "user",
            "content" => [{ "type" => "text", "text" => "Can you you tell me a joke? Respond in json." }]
          }
        ])
        expect(model_completion.llm_model_key).to eq("open_router_llama_3_1_8b_instruct")
        expect(model_completion.model_api_name).to eq("meta-llama/llama-3.1-8b-instruct")

        expect(deltas).to eq([
          "{\n  \"joke\":",
          " \"Why don't",
          " scientists",
          " trust atoms",
          "? Because they",
          " make up everything",
          "!\"\n}"
        ])
      end

      it "streams a response with tool calls correctly", vcr: { cassette_name: "open_router/streaming_tool_calls" } do
        llm = Raif.llm(:open_router_llama_3_3_70b_instruct)
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        # we're not accumulating deltas for tool calls since it seems like a bad idea to execute the tool call before arguments are complete
        expect(deltas).to eq([])

        expect(model_completion.raw_response).to eq(nil)
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])

        expect(model_completion.response_array).to eq([{
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [{
              "id" => "call_abc123",
              "type" => "function",
              "function" => { "name" => "fetch_url", "arguments" => "{\"url\": \"https://www.wsj.com/\"}" }
            }],
          },
          "finish_reason" => "stop"
        }])

        expect(model_completion.response_tool_calls).to eq([{
          "provider_tool_call_id" => "call_abc123",
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com/" }
        }])

        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{
          "content" => [{ "text" => "What's on the homepage of https://www.wsj.com today?", "type" => "text" }],
          "role" => "user"
        }])
        expect(model_completion.llm_model_key).to eq("open_router_llama_3_3_70b_instruct")
        expect(model_completion.model_api_name).to eq("meta-llama/llama-3.3-70b-instruct")
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
        expect(params[:stream]).to eq(nil)
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
