# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::XAi, type: :model do
  it_behaves_like "an LLM that uses OpenAI's Completions API message formatting"
  it_behaves_like "an LLM that uses OpenAI's Completions API tool formatting"

  let(:llm){ Raif.llm(:x_ai_grok_4_3) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
    allow(Raif.config).to receive(:x_ai_api_key){ ENV["X_AI_API_KEY"] }
  end

  describe "#update_model_completion" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        llm_model_key: "x_ai_grok_4_3",
        model_api_name: "grok-4.3"
      )
    end

    def response_json_with_finish_reason(finish_reason)
      {
        "id" => "gen-123",
        "choices" => [
          {
            "index" => 0,
            "message" => { "role" => "assistant", "content" => "Hello" },
            "finish_reason" => finish_reason
          }
        ],
        "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
      }
    end

    it "stores the finish reason and flags a length-limited response as truncated" do
      llm.send(:update_model_completion, model_completion, response_json_with_finish_reason("length"))

      expect(model_completion.response_finish_reason).to eq("length")
      expect(model_completion).to be_truncated
    end

    it "does not flag a normally completed response as truncated" do
      llm.send(:update_model_completion, model_completion, response_json_with_finish_reason("stop"))

      expect(model_completion.response_finish_reason).to eq("stop")
      expect(model_completion).not_to be_truncated
    end
  end

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the xAI API and processes the text response", vcr: { cassette_name: "x_ai/text_response" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")

        expect(model_completion.raw_response).to be_present
        expect(model_completion.completion_tokens).to be > 0
        expect(model_completion.prompt_tokens).to be > 0
        expect(model_completion.total_tokens).to be > 0
        expect(model_completion.llm_model_key).to eq("x_ai_grok_4_3")
        expect(model_completion.model_api_name).to eq("grok-4.3")
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

    context "when the response format is json and the source has a json_response_schema" do
      let(:test_task){ Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      it "sends response_format: json_schema, parses the structured response, and adds no synthetic tool calls",
        vcr: { cassette_name: "x_ai/json_response_with_schema" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Tell me a joke" }],
          response_format: :json,
          source: test_task
        )

        expect(model_completion.response_format).to eq("json")
        expect(model_completion.response_format_parameter).to eq("json_schema")
        expect(model_completion.parsed_response).to eq({
          "joke" => "Why don't scientists trust atoms?",
          "answer" => "Because they make up everything."
        })
        expect(model_completion.response_tool_calls).to be_nil
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
        expect(model_completion.llm_model_key).to eq("x_ai_grok_4_3")
        expect(model_completion.model_api_name).to eq("grok-4.3")
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
          llm_model_key: "x_ai_grok_4_3",
          model_api_name: "grok-4.3",
          temperature: 0.5
        )
      end

      it "builds the correct parameters with system prompt" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:model]).to eq("grok-4.3")
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
          llm_model_key: "x_ai_grok_4_3",
          model_api_name: "grok-4.3",
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

    context "with tools and tool_choice" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "I need information" }],
          llm_model_key: "x_ai_grok_4_3",
          model_api_name: "grok-4.3",
          available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::AgentFinalAnswer]
        )
      end

      let(:params) { llm.send(:build_request_parameters, model_completion) }

      context "when tool_choice is 'required'" do
        before { model_completion.tool_choice = "required" }

        it "sets tool_choice to 'required' and disables parallel tool calls" do
          expect(params[:tool_choice]).to eq("required")
          expect(params[:parallel_tool_calls]).to eq(false)
        end

        it "enables parallel tool calls when the completion allows them" do
          model_completion.allow_parallel_tool_calls = true
          expect(params[:parallel_tool_calls]).to eq(true)
        end
      end

      context "when a specific tool is forced" do
        before { model_completion.tool_choice = "Raif::ModelTools::AgentFinalAnswer" }

        it "forces the tool and disables parallel tool calls" do
          expect(params[:tool_choice]).to eq({ "type" => "function", "function" => { "name" => "agent_final_answer" } })
          expect(params[:parallel_tool_calls]).to eq(false)
        end
      end

      context "when tool_choice is not set" do
        it "disables parallel tool calls by default" do
          expect(params[:parallel_tool_calls]).to eq(false)
        end

        it "enables parallel tool calls when the completion allows them" do
          model_completion.allow_parallel_tool_calls = true
          expect(params[:parallel_tool_calls]).to eq(true)
        end
      end
    end

    context "with a json_response_schema present" do
      let(:test_task){ Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Tell me a joke" }],
          llm_model_key: "x_ai_grok_4_3",
          model_api_name: "grok-4.3",
          response_format: "json",
          source: test_task
        )
      end

      it "sends response_format: json_schema with strict:true and the source's schema" do
        params = llm.send(:build_request_parameters, model_completion)

        expect(params[:response_format]).to eq({
          type: "json_schema",
          json_schema: {
            name: "json_response_schema",
            strict: true,
            schema: model_completion.json_response_schema,
          },
        })
      end

      it "does not add a synthetic json_response function-tool to params[:tools]" do
        params = llm.send(:build_request_parameters, model_completion)

        if params[:tools].present?
          tool_names = params[:tools].map{|t| t.dig(:function, :name) }
          expect(tool_names).not_to include("json_response")
        else
          expect(params[:tools]).to be_blank
        end
      end

      it "sets model_completion.response_format_parameter to 'json_schema'" do
        llm.send(:build_request_parameters, model_completion)
        expect(model_completion.response_format_parameter).to eq("json_schema")
      end

      it "raises Raif::Errors::OpenAi::JsonSchemaError when the schema does not satisfy strict-mode constraints" do
        invalid_schema = { type: "object", properties: { joke: { type: "string" } } }
        allow(model_completion).to receive(:json_response_schema).and_return(invalid_schema)

        expect do
          llm.send(:build_request_parameters, model_completion)
        end.to raise_error(Raif::Errors::OpenAi::JsonSchemaError)
      end
    end

    context "when response_format is :json but no json_response_schema is present (fallback)" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Tell me a joke" }],
          llm_model_key: "x_ai_grok_4_3",
          model_api_name: "grok-4.3",
          response_format: "json"
        )
      end

      it "falls back to response_format: { type: 'json_object' }" do
        params = llm.send(:build_request_parameters, model_completion)
        expect(params[:response_format]).to eq({ type: "json_object" })
        expect(model_completion.response_format_parameter).to eq("json_object")
      end
    end
  end

  describe "#update_model_completion" do
    let(:json_payload){ '{"joke":"Why don\'t scientists trust atoms?","answer":"Because they make up everything."}' }
    let(:response_json) do
      {
        "id" => "chatcmpl-xai-test-1",
        "choices" => [
          {
            "index" => 0,
            "finish_reason" => "stop",
            "message" => {
              "role" => "assistant",
              "content" => json_payload,
              "refusal" => nil,
            },
          },
        ],
        "usage" => {
          "completion_tokens" => 27,
          "prompt_tokens" => 55,
          "total_tokens" => 82,
          "prompt_tokens_details" => { "cached_tokens" => 12 },
        },
      }
    end

    it "populates raw_response from message.content and reads usage off the response" do
      model_completion = Raif::ModelCompletion.create!(
        messages: [{ "role" => "user", "content" => "Tell me a joke" }],
        llm_model_key: "x_ai_grok_4_3",
        model_api_name: "grok-4.3",
        response_format: "json",
      )

      llm.send(:update_model_completion, model_completion, response_json)
      model_completion.reload

      expect(model_completion.raw_response).to eq(json_payload)
      expect(model_completion.parsed_response).to eq({
        "joke" => "Why don't scientists trust atoms?",
        "answer" => "Because they make up everything.",
      })
      expect(model_completion.response_tool_calls).to be_nil
      expect(model_completion.completion_tokens).to eq(27)
      expect(model_completion.prompt_tokens).to eq(55)
      expect(model_completion.total_tokens).to eq(82)
      expect(model_completion.cache_read_input_tokens).to eq(12)
      expect(model_completion.response_id).to eq("chatcmpl-xai-test-1")
      expect(model_completion.response_array).to eq(response_json["choices"])
    end

    context "when the response includes reasoning_tokens" do
      let(:reasoning_response_json) do
        response_json.deep_merge(
          "usage" => {
            "completion_tokens" => 9,
            "prompt_tokens" => 140,
            "total_tokens" => 259,
            "completion_tokens_details" => { "reasoning_tokens" => 110 },
          }
        )
      end

      it "adds reasoning_tokens to completion_tokens so cost reflects what xAI bills" do
        model_completion = Raif::ModelCompletion.create!(
          messages: [{ "role" => "user", "content" => "Hello" }],
          llm_model_key: "x_ai_grok_4_3",
          model_api_name: "grok-4.3",
          response_format: "text",
        )

        llm.send(:update_model_completion, model_completion, reasoning_response_json)
        model_completion.reload

        # xAI's completion_tokens (9) excludes reasoning_tokens (110); we roll
        # them together so Raif::ModelCompletion#calculate_costs charges the
        # combined output at the output token rate.
        expect(model_completion.completion_tokens).to eq(119)
        expect(model_completion.prompt_tokens).to eq(140)
        expect(model_completion.total_tokens).to eq(259)

        config = Raif.llm_config(:x_ai_grok_4_3)
        expected_output_cost = (config[:output_token_cost] * 119).round(6)
        expect(model_completion.output_token_cost.to_f).to be_within(1e-6).of(expected_output_cost)
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
