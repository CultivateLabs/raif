# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::OpenRouter, type: :model do
  it_behaves_like "an LLM that uses OpenAI's message formatting"

  let(:llm){ Raif.llm(:open_router_claude_3_7_sonnet) }
  let(:mock_connection) { instance_double(Faraday::Connection) }
  let(:mock_response) { instance_double(Faraday::Response) }

  before do
    allow(Faraday).to receive(:new).and_return(mock_connection)
    allow(mock_connection).to receive(:post).and_return(mock_response)
    allow(mock_response).to receive(:success?).and_return(true)
  end

  describe "#chat" do
    context "when the response format is text" do
      let(:response_body) do
        {
          "choices" => [{ "message" => { "content" => "Response content" } }],
          "usage" => { "completion_tokens" => 10, "prompt_tokens" => 5, "total_tokens" => 15 }
        }
      end

      let(:mock_request) { double("Request") }

      before do
        allow(mock_response).to receive(:body).and_return(response_body)
        allow(mock_connection).to receive(:post).and_yield(mock_request).and_return(mock_response)
        allow(mock_request).to receive(:body=)
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
      end
    end

    context "when the API returns an error" do
      let(:error_response_body) do
        {
          "error" => {
            "message" => "API rate limit exceeded",
            "type" => "rate_limit_error"
          }
        }
      end

      let(:mock_request) { double("Request") }

      before do
        allow(mock_response).to receive(:success?).and_return(false)
        allow(mock_response).to receive(:status).and_return(429)
        allow(mock_response).to receive(:body).and_return(error_response_body)
        allow(mock_connection).to receive(:post).and_yield(mock_request).and_return(mock_response)
        allow(mock_request).to receive(:body=)
      end

      it "raises an ApiError with the error message" do
        expect do
          llm.chat(message: "Hello")
        end.to raise_error(Raif::Errors::OpenRouter::ApiError, "API rate limit exceeded")
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
        expect(tool_call["id"]).to eq("call_123")
        expect(tool_call["type"]).to eq("function")
        expect(tool_call["function"]["name"]).to eq("test_tool")
        expect(tool_call["function"]["arguments"]).to eq("{\"query\":\"test query\"}")
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

      it "returns an empty array" do
        tool_calls = llm.send(:extract_response_tool_calls, response_json)

        expect(tool_calls).to be_an(Array)
        expect(tool_calls).to be_empty
      end
    end
  end
end
