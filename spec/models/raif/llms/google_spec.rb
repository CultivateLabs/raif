# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Google, type: :model do
  let(:llm) { Raif.llm(:google_gemini_2_5_flash) }

  before do
    allow(Raif.config).to receive(:llm_api_requests_enabled) { true }
    allow(Raif.config).to receive(:google_models_enabled) { true }
    allow(Raif.config).to receive(:google_api_key) { ENV["GOOGLE_AI_API_KEY"] }
  end

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the Google API and processes the response", vcr: { cassette_name: "google/format_text" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant")

        expect(model_completion.raw_response).to eq("Hello there! How can I help you today?")
        expect(model_completion.completion_tokens).to eq(10)
        expect(model_completion.prompt_tokens).to eq(7)
        expect(model_completion.total_tokens).to eq(17)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{ "role" => "user", "parts" => [{ "text" => "Hello" }] }])
        expect(model_completion.system_prompt).to eq("You are a helpful assistant")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.max_completion_tokens).to eq(nil)
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.source).to be_nil
        expect(model_completion.llm_model_key).to eq("google_gemini_2_5_flash")
        expect(model_completion.model_api_name).to eq("gemini-2.5-flash")
        expect(model_completion.response_format_parameter).to be_nil
        expect(model_completion.response_array).to eq([{ "text" => "Hello there! How can I help you today?" }])
      end
    end

    context "when the response format is json" do
      it "makes a request to the Google API and processes the response", vcr: { cassette_name: "google/format_json" } do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hello! How can I assist you today?" },
          { role: "user", content: "Can you tell me a joke? Respond in json." }
        ]

        system_prompt = <<~PROMPT.squish
          You are a helpful assistant who specializes in telling jokes. Your response should be a properly
          formatted JSON object containing a single `joke` key. Do not include any other text in your
          response outside the JSON object.
        PROMPT

        model_completion = llm.chat(messages: messages, response_format: :json, system_prompt: system_prompt)

        expected_raw_response = <<~RESPONSE.chomp
          ```json
          {
            "joke": "Why don't scientists trust atoms? Because they make up everything!"
          }
          ```
        RESPONSE
        expect(model_completion.raw_response).to eq(expected_raw_response)
        expect(model_completion.parsed_response).to eq({
          "joke" => "Why don't scientists trust atoms? Because they make up everything!"
        })
        expect(model_completion.completion_tokens).to eq(28)
        expect(model_completion.prompt_tokens).to eq(66)
        expect(model_completion.total_tokens).to eq(138)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([
          { "role" => "user", "parts" => [{ "text" => "Hello" }] },
          { "role" => "model", "parts" => [{ "text" => "Hello! How can I assist you today?" }] },
          { "role" => "user", "parts" => [{ "text" => "Can you tell me a joke? Respond in json." }] }
        ])
        expect(model_completion.system_prompt).to eq(system_prompt)
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.max_completion_tokens).to eq(nil)
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.source).to be_nil
        expect(model_completion.llm_model_key).to eq("google_gemini_2_5_flash")
        expect(model_completion.model_api_name).to eq("gemini-2.5-flash")
      end
    end

    context "when using developer-managed tools" do
      it "extracts tool calls correctly", vcr: { cassette_name: "google/developer_managed_fetch_url" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_tool_calls.length).to eq(1)
        expect(model_completion.response_tool_calls.first["name"]).to eq("fetch_url")
        expect(model_completion.response_tool_calls.first["arguments"]).to eq({ "url" => "https://www.wsj.com" })
        expect(model_completion.response_tool_calls.first["provider_tool_call_id"]).to be_present
        expect(model_completion.completion_tokens).to eq(22)
        expect(model_completion.prompt_tokens).to eq(65)
        # total_tokens includes thoughtsTokenCount (54) in addition to prompt + completion
        expect(model_completion.total_tokens).to eq(141)
        # raw_response should be blank when only tool calls are returned
        expect(model_completion.raw_response).to be_blank
      end

      it "forces tool use with tool_choice", vcr: { cassette_name: "google/forced_tool_choice" } do
        # Use a prompt that wouldn't naturally trigger fetch_url, but force it anyway
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Tell me about the Ruby programming language" }],
          available_model_tools: [Raif::ModelTools::FetchUrl],
          tool_choice: "Raif::ModelTools::FetchUrl"
        )

        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.tool_choice).to eq("Raif::ModelTools::FetchUrl")
        # The model should be forced to call the tool even though the prompt doesn't naturally suggest it
        expect(model_completion.response_tool_calls.length).to eq(1)
        expect(model_completion.response_tool_calls.first["name"]).to eq("fetch_url")
        expect(model_completion.response_tool_calls.first["arguments"]).to have_key("url")
        expect(model_completion.response_tool_calls.first["provider_tool_call_id"]).to be_present
      end
    end

    context "when using provider-managed tools" do
      it "extracts web search results correctly", vcr: { cassette_name: "google/provider_managed_web_search" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }],
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )

        expect(model_completion.raw_response).to be_present
        expect(model_completion.raw_response).to include("Ruby on Rails 8.1")
        expect(model_completion.raw_response).to include("Ruby on Rails 8.0")
        expect(model_completion.raw_response).to include("Ruby on Rails 7.2")
        expect(model_completion.raw_response).to include("Ruby on Rails 7.1")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::ProviderManaged::WebSearch"])
        expect(model_completion.completion_tokens).to eq(1038)
        expect(model_completion.prompt_tokens).to eq(11)
        # total_tokens includes thoughtsTokenCount (208) and toolUsePromptTokenCount (157)
        expect(model_completion.total_tokens).to eq(1414)

        # Test that citations are extracted from grounding metadata
        expect(model_completion.citations).to be_an(Array)
        expect(model_completion.citations.length).to eq(12)
        expect(model_completion.citations.first).to have_key("url")
        expect(model_completion.citations.first).to have_key("title")
        expect(model_completion.citations.first["title"]).to eq("wikipedia.org")

        # Verify citation sources include expected domains
        citation_titles = model_completion.citations.map { |c| c["title"] }
        expect(citation_titles).to include("wikipedia.org")
        expect(citation_titles).to include("rubyonrails.org")
      end
    end

    context "streaming" do
      before do
        allow(Raif.config).to receive(:streaming_update_chunk_size_threshold).and_return(10)
      end

      it "streams a text response correctly", vcr: { cassette_name: "google/streaming_text" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Please write me a poem" }]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(deltas).to eq([
          "The world awakes with whispered sigh,\nA gentle breath upon the air.\nWhere morning mists begin to lie,\nAnd banish shadows everywhere.\n\nThe sunbeams stretch their golden fingers,\nTo paint the dew on leaf and", # rubocop:disable Layout/LineLength
          " bloom,\nWhile distant song a robin lingers,\nDispelling all the fading gloom.\n\nA quiet peace begins to settle,\nUpon the heart, a gentle balm.\nNo urgency, no need to meddle,\nJust nature", # rubocop:disable Layout/LineLength
          "'s soft and timeless calm.\n\nSo take a moment, soft and deep,\nTo breathe it in, this world so fair.\nWhile secret promises it keeps,\nAnd wonders wait beyond compare." # rubocop:disable Layout/LineLength
        ])

        expect(model_completion.raw_response).to eq("The world awakes with whispered sigh,\nA gentle breath upon the air.\nWhere morning mists begin to lie,\nAnd banish shadows everywhere.\n\nThe sunbeams stretch their golden fingers,\nTo paint the dew on leaf and bloom,\nWhile distant song a robin lingers,\nDispelling all the fading gloom.\n\nA quiet peace begins to settle,\nUpon the heart, a gentle balm.\nNo urgency, no need to meddle,\nJust nature's soft and timeless calm.\n\nSo take a moment, soft and deep,\nTo breathe it in, this world so fair.\nWhile secret promises it keeps,\nAnd wonders wait beyond compare.") # rubocop:disable Layout/LineLength
        expect(model_completion.completion_tokens).to eq(139)
        expect(model_completion.prompt_tokens).to eq(6)
        # total_tokens includes thoughtsTokenCount (1338) in addition to prompt + completion
        expect(model_completion.total_tokens).to eq(1483)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{ "role" => "user", "parts" => [{ "text" => "Please write me a poem" }] }])
      end

      it "streams a json response correctly", vcr: { cassette_name: "google/streaming_json" } do
        system_prompt = <<~PROMPT.squish
          You are a helpful assistant who specializes in telling jokes. Your response should be a properly
          formatted JSON object containing a single `joke` key. Do not include any other text in your
          response outside the JSON object.
        PROMPT

        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you tell me a joke? Respond in json." }],
          system_prompt: system_prompt,
          response_format: :json
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expected_raw_response = <<~RESPONSE.chomp
          ```json
          {
            "joke": "Why don't scientists trust atoms? Because they make up everything!"
          }
          ```
        RESPONSE
        expect(model_completion.raw_response).to eq(expected_raw_response)
        expect(model_completion.parsed_response).to eq({
          "joke" => "Why don't scientists trust atoms? Because they make up everything!"
        })
        expect(model_completion.completion_tokens).to eq(28)
        expect(model_completion.prompt_tokens).to eq(54)
        # total_tokens includes thoughtsTokenCount (50) in addition to prompt + completion
        expect(model_completion.total_tokens).to eq(132)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{
          "role" => "user",
          "parts" => [{ "text" => "Can you tell me a joke? Respond in json." }]
        }])

        expect(deltas).not_to be_empty
      end

      it "streams a response with tool calls correctly", vcr: { cassette_name: "google/streaming_tool_calls" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_tool_calls.length).to eq(1)
        expect(model_completion.response_tool_calls.first["name"]).to eq("fetch_url")
        expect(model_completion.response_tool_calls.first["arguments"]).to eq({ "url" => "https://www.wsj.com" })
        expect(model_completion.response_tool_calls.first["provider_tool_call_id"]).to be_present
        expect(model_completion.completion_tokens).to eq(22)
        expect(model_completion.prompt_tokens).to eq(65)
        # total_tokens includes thoughtsTokenCount (54) in addition to prompt + completion
        expect(model_completion.total_tokens).to eq(141)
        # raw_response should be blank when only tool calls are returned
        expect(model_completion.raw_response).to be_blank

        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{
          "role" => "user",
          "parts" => [{ "text" => "What's on the homepage of https://www.wsj.com today?" }]
        }])
      end
    end

    context "error handling" do
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
                "message": "API rate limit exceeded",
                "code": 429
              }
            }
          JSON
        end

        before do
          stubs.post(%r{models/.*:generateContent}) do |_env|
            raise Faraday::ClientError.new(
              "Rate limited",
              { status: 429, body: error_response_body }
            )
          end

          allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
        end

        it "raises a Faraday::ClientError with the error message" do
          expect do
            llm.chat(messages: [{ role: "user", content: "Hello" }])
          end.to raise_error(Faraday::ClientError)
        end
      end

      context "when the API returns a 500-level error" do
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
          stubs.post(%r{models/.*:generateContent}) do |_env|
            raise Faraday::ServerError.new(
              "Internal server error",
              { status: 500, body: error_response_body }
            )
          end

          allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
        end

        it "raises a Faraday::ServerError with the error message" do
          expect do
            llm.chat(messages: [{ role: "user", content: "Hello" }])
          end.to raise_error(Faraday::ServerError, "Internal server error")
        end
      end
    end
  end

  describe "#build_request_parameters" do
    let(:parameters) { llm.send(:build_request_parameters, model_completion) }

    context "for text response format" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "google_gemini_2_5_flash",
          model_api_name: "gemini-2.5-flash",
          temperature: 0.8,
          response_format: "text",
          system_prompt: system_prompt
        )
      end

      context "with system prompt" do
        let(:system_prompt) { "You are a helpful assistant" }

        it "includes system_instruction in the parameters" do
          expect(parameters[:contents]).to eq([{ "role" => "user", "content" => "Hello" }])
          expect(parameters[:system_instruction]).to eq({ parts: [{ text: "You are a helpful assistant" }] })
          expect(parameters[:generationConfig][:temperature]).to eq(0.8)
        end
      end

      context "without system prompt" do
        let(:system_prompt) { nil }

        it "builds parameters without system_instruction" do
          expect(parameters[:contents]).to eq([{ "role" => "user", "content" => "Hello" }])
          expect(parameters).not_to have_key(:system_instruction)
        end
      end
    end

    context "for JSON response format" do
      let(:system_prompt) { "You are a helpful assistant" }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: system_prompt,
          llm_model_key: "google_gemini_2_5_flash",
          model_api_name: "gemini-2.5-flash",
          temperature: 0.5,
          response_format: "json"
        )
      end

      context "when the model completion has a json_response_schema" do
        before do
          model_completion.source = Raif::TestJsonTask.new
        end

        it "includes responseSchema in generationConfig" do
          expect(parameters[:generationConfig][:responseMimeType]).to eq("application/json")
          expect(parameters[:generationConfig][:responseSchema]).to be_present
        end
      end

      context "when the model completion does not have a json_response_schema" do
        it "does not include responseSchema" do
          expect(model_completion.json_response_schema).to be_nil
          expect(parameters[:generationConfig]).not_to have_key(:responseSchema)
        end

        it "does not include responseMimeType in generationConfig" do
          expect(parameters[:generationConfig]).not_to have_key(:responseMimeType)
        end
      end
    end

    context "with max_completion_tokens" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "google_gemini_2_5_flash",
          model_api_name: "gemini-2.5-flash",
          temperature: 0.8,
          response_format: "text",
          max_completion_tokens: 1000
        )
      end

      it "includes maxOutputTokens in generationConfig" do
        expect(parameters[:generationConfig][:maxOutputTokens]).to eq(1000)
      end
    end

    context "with tools" do
      let(:model_completion) do
        mc = Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "google_gemini_2_5_flash",
          model_api_name: "gemini-2.5-flash",
          temperature: 0.8,
          response_format: "text"
        )
        allow(mc).to receive(:available_model_tools).and_return(["Raif::TestModelTool"])
        mc
      end

      before do
        allow(llm).to receive(:supports_native_tool_use?).and_return(true)
      end

      it "includes tools in the parameters" do
        expect(parameters[:tools]).to include({
          functionDeclarations: [{
            name: "test_model_tool",
            description: "Mock Tool Description",
            parameters: {
              type: "object",
              required: ["items"],
              properties: {
                items: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      title: { type: "string", description: "The title of the item" },
                      description: { type: "string" }
                    },
                    required: ["title", "description"]
                  }
                }
              }
            }
          }]
        })
      end
    end

    context "with tool_choice (forced tool calling)" do
      let(:model_completion) do
        mc = Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "google_gemini_2_5_flash",
          model_api_name: "gemini-2.5-flash",
          temperature: 0.8,
          response_format: "text",
          tool_choice: "Raif::TestModelTool"
        )
        allow(mc).to receive(:available_model_tools).and_return(["Raif::TestModelTool"])
        mc
      end

      before do
        allow(llm).to receive(:supports_native_tool_use?).and_return(true)
      end

      it "includes toolConfig with functionCallingConfig to force the specified tool" do
        expect(parameters[:toolConfig]).to eq({
          functionCallingConfig: {
            mode: "ANY",
            allowedFunctionNames: ["test_model_tool"]
          }
        })
      end

      it "still includes the tools in the parameters" do
        expect(parameters[:tools]).to be_present
        expect(parameters[:tools].first[:functionDeclarations].first[:name]).to eq("test_model_tool")
      end
    end
  end

  describe "#build_tools_parameter" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "google_gemini_2_5_flash",
        model_api_name: "gemini-2.5-flash",
        available_model_tools: available_model_tools
      )
    end

    context "with no tools" do
      let(:available_model_tools) { [] }

      it "returns an empty array" do
        result = llm.send(:build_tools_parameter, model_completion)
        expect(result).to eq([])
      end
    end

    context "with developer-managed tools" do
      let(:available_model_tools) { [Raif::TestModelTool] }

      it "formats developer-managed tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq([{
          functionDeclarations: [{
            name: "test_model_tool",
            description: "Mock Tool Description",
            parameters: {
              type: "object",
              required: ["items"],
              properties: {
                items: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      title: { type: "string", description: "The title of the item" },
                      description: { type: "string" }
                    },
                    required: ["title", "description"]
                  }
                }
              }
            }
          }]
        }])
      end
    end

    context "with provider-managed tools" do
      context "with WebSearch tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::WebSearch] }

        it "formats WebSearch tool correctly" do
          result = llm.send(:build_tools_parameter, model_completion)

          expect(result).to eq([{ google_search: {} }])
        end
      end

      context "with CodeExecution tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::CodeExecution] }

        it "formats CodeExecution tool correctly" do
          result = llm.send(:build_tools_parameter, model_completion)

          expect(result).to eq([{ code_execution: {} }])
        end
      end

      context "with ImageGeneration tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::ImageGeneration] }

        it "raises Raif::Errors::UnsupportedFeatureError" do
          expect do
            llm.send(:build_tools_parameter, model_completion)
          end.to raise_error(Raif::Errors::UnsupportedFeatureError)
        end
      end
    end

    context "with mixed tool types" do
      let(:available_model_tools) { [Raif::TestModelTool, Raif::ModelTools::ProviderManaged::WebSearch] }

      it "formats all tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to contain_exactly(
          { google_search: {} },
          {
            functionDeclarations: [{
              name: "test_model_tool",
              description: "Mock Tool Description",
              parameters: {
                type: "object",
                required: ["items"],
                properties: {
                  items: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        title: { type: "string", description: "The title of the item" },
                        description: { type: "string" }
                      },
                      required: ["title", "description"]
                    }
                  }
                }
              }
            }]
          }
        )
      end
    end

    context "when native tool use is not supported" do
      let(:available_model_tools) { [Raif::TestModelTool] }

      before do
        allow(llm).to receive(:supports_native_tool_use?).and_return(false)
      end

      it "does not include developer-managed tools" do
        result = llm.send(:build_tools_parameter, model_completion)
        expect(result).to eq([])
      end
    end
  end

  describe "#format_messages" do
    it "formats the messages correctly with a string as the content" do
      messages = [{ "role" => "user", "content" => "Hello" }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([{ "role" => "user", "parts" => [{ "text" => "Hello" }] }])
    end

    it "formats the messages correctly with an array as the content" do
      messages = [{ "role" => "user", "content" => ["Hello", "World"] }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [
            { "text" => "Hello" },
            { "text" => "World" }
          ]
        }
      ])
    end

    it "converts assistant role to model" do
      messages = [{ "role" => "assistant", "content" => "Hello" }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([{ "role" => "model", "parts" => [{ "text" => "Hello" }] }])
    end

    it "formats the messages correctly with an image from file" do
      image_path = Raif::Engine.root.join("spec/fixtures/files/cultivate.png")
      image = Raif::ModelImageInput.new(input: image_path)
      messages = [{
        "role" => "user",
        "content" => [
          "What is in this image?",
          image
        ]
      }]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [
            { "text" => "What is in this image?" },
            {
              "inlineData" => {
                "mimeType" => "image/png",
                "data" => Base64.strict_encode64(File.read(image_path))
              }
            }
          ]
        }
      ])
    end

    it "formats the messages correctly when using image_url" do
      image_url = "https://example.com/image.png"
      image = Raif::ModelImageInput.new(url: image_url)
      messages = [{ "role" => "user", "content" => [image] }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [
            {
              "fileData" => {
                "mimeType" => nil,
                "fileUri" => image_url
              }
            }
          ]
        }
      ])
    end

    it "formats the messages correctly with a file" do
      file_path = Raif::Engine.root.join("spec/fixtures/files/test.pdf")
      file = Raif::ModelFileInput.new(input: file_path)
      messages = [{
        "role" => "user",
        "content" => [
          "What's in this file?",
          file
        ]
      }]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [
            { "text" => "What's in this file?" },
            {
              "inlineData" => {
                "mimeType" => "application/pdf",
                "data" => Base64.strict_encode64(File.read(file_path))
              }
            }
          ]
        }
      ])
    end

    it "formats the messages correctly when using file_url" do
      file_url = "https://example.com/file.pdf"
      file = Raif::ModelFileInput.new(url: file_url)
      messages = [{ "role" => "user", "content" => [file] }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [
            {
              "fileData" => {
                "mimeType" => nil,
                "fileUri" => file_url
              }
            }
          ]
        }
      ])
    end

    it "formats tool call messages correctly" do
      tool_call = {
        "type" => "tool_call",
        "provider_tool_call_id" => "call_123",
        "name" => "fetch_url",
        "arguments" => { "url" => "https://example.com" },
        "assistant_message" => "I'll fetch that for you."
      }
      messages = [tool_call]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "model",
          "parts" => [
            { "text" => "I'll fetch that for you." },
            {
              "functionCall" => {
                "name" => "fetch_url",
                "args" => { "url" => "https://example.com" }
              }
            }
          ]
        }
      ])
    end

    it "formats tool call result messages correctly" do
      tool_call_result = {
        "type" => "tool_call_result",
        "provider_tool_call_id" => "call_123",
        "name" => "fetch_url",
        "result" => { "content" => "Page content here" }
      }
      messages = [tool_call_result]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [{
            "functionResponse" => {
              "name" => "fetch_url",
              "response" => { "content" => "Page content here" }
            }
          }]
        }
      ])
    end

    it "formats tool call result messages with string result correctly" do
      tool_call_result = {
        "type" => "tool_call_result",
        "provider_tool_call_id" => "call_123",
        "name" => "fetch_url",
        "result" => "Page content here"
      }
      messages = [tool_call_result]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "parts" => [{
            "functionResponse" => {
              "name" => "fetch_url",
              "response" => { "output" => "Page content here" }
            }
          }]
        }
      ])
    end
  end

  describe "#build_forced_tool_choice" do
    it "returns the correct format for forcing a specific tool" do
      result = llm.build_forced_tool_choice("agent_final_answer")
      expect(result).to eq({ mode: "ANY", allowedFunctionNames: ["agent_final_answer"] })
    end
  end

  describe "#extract_citations" do
    context "with grounding metadata in response" do
      it "extracts citations from grounding chunks" do
        response_json = {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Based on the search results..." }],
              "role" => "model"
            },
            "groundingMetadata" => {
              "groundingChunks" => [
                {
                  "web" => {
                    "uri" => "https://example.com/page1",
                    "title" => "Example Page 1"
                  }
                },
                {
                  "web" => {
                    "uri" => "https://example.com/page2",
                    "title" => "Example Page 2"
                  }
                }
              ]
            }
          }]
        }

        citations = llm.send(:extract_citations, response_json)

        expect(citations).to contain_exactly(
          { "url" => "https://example.com/page1", "title" => "Example Page 1" },
          { "url" => "https://example.com/page2", "title" => "Example Page 2" }
        )
      end

      it "removes duplicate citations by URL" do
        response_json = {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Response text" }],
              "role" => "model"
            },
            "groundingMetadata" => {
              "groundingChunks" => [
                {
                  "web" => {
                    "uri" => "https://example.com/same-url",
                    "title" => "First Title"
                  }
                },
                {
                  "web" => {
                    "uri" => "https://example.com/same-url",
                    "title" => "Second Title"
                  }
                }
              ]
            }
          }]
        }

        citations = llm.send(:extract_citations, response_json)

        expect(citations).to eq([
          { "url" => "https://example.com/same-url", "title" => "First Title" }
        ])
      end
    end

    context "without grounding metadata in response" do
      it "returns empty array when no grounding metadata" do
        response_json = {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Response without grounding" }],
              "role" => "model"
            }
          }]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end

      it "returns empty array when grounding chunks are empty" do
        response_json = {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Response" }],
              "role" => "model"
            },
            "groundingMetadata" => {
              "groundingChunks" => []
            }
          }]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end
    end
  end

  describe "#extract_response_tool_calls" do
    context "when response has no candidates" do
      let(:response) { { "candidates" => nil } }

      it "returns nil" do
        expect(llm.send(:extract_response_tool_calls, response)).to be_nil
      end
    end

    context "when response has empty candidates" do
      let(:response) { { "candidates" => [] } }

      it "returns nil" do
        expect(llm.send(:extract_response_tool_calls, response)).to be_nil
      end
    end

    context "when response has only text parts" do
      let(:response) do
        {
          "candidates" => [{
            "content" => {
              "parts" => [{ "text" => "Hello" }],
              "role" => "model"
            }
          }]
        }
      end

      it "returns nil" do
        expect(llm.send(:extract_response_tool_calls, response)).to be_nil
      end
    end

    context "when response has function call parts" do
      let(:response) do
        {
          "candidates" => [{
            "content" => {
              "parts" => [
                { "text" => "I'll help you with that." },
                {
                  "functionCall" => {
                    "name" => "get_weather",
                    "args" => { "location" => "San Francisco" }
                  }
                }
              ],
              "role" => "model"
            }
          }]
        }
      end

      it "extracts function calls correctly" do
        result = llm.send(:extract_response_tool_calls, response)
        expect(result.length).to eq(1)
        expect(result.first["name"]).to eq("get_weather")
        expect(result.first["arguments"]).to eq({ "location" => "San Francisco" })
        expect(result.first["provider_tool_call_id"]).to be_present
      end
    end
  end

  describe "#extract_raw_response" do
    context "when response has no candidates" do
      let(:response) { { "candidates" => nil } }

      it "returns nil" do
        expect(llm.send(:extract_text_response, response)).to be_nil
      end
    end

    context "when response has empty candidates" do
      let(:response) { { "candidates" => [] } }

      it "returns nil" do
        expect(llm.send(:extract_text_response, response)).to be_nil
      end
    end

    context "when response has only function calls" do
      let(:response) do
        {
          "candidates" => [{
            "content" => {
              "parts" => [{
                "functionCall" => {
                  "name" => "get_weather",
                  "args" => { "location" => "San Francisco" }
                }
              }],
              "role" => "model"
            }
          }]
        }
      end

      it "returns nil" do
        expect(llm.send(:extract_text_response, response)).to be_blank
      end
    end

    context "when response has text parts" do
      let(:response) do
        {
          "candidates" => [{
            "content" => {
              "parts" => [
                { "text" => "Hello" },
                { "text" => "World" }
              ],
              "role" => "model"
            }
          }]
        }
      end

      it "extracts and joins text content" do
        result = llm.send(:extract_text_response, response)
        expect(result).to eq("HelloWorld")
      end
    end

    context "when response has mixed content types" do
      let(:response) do
        {
          "candidates" => [{
            "content" => {
              "parts" => [
                { "text" => "Text content" },
                {
                  "functionCall" => {
                    "name" => "some_function",
                    "args" => {}
                  }
                }
              ],
              "role" => "model"
            }
          }]
        }
      end

      it "only extracts text content" do
        result = llm.send(:extract_text_response, response)
        expect(result).to eq("Text content")
      end
    end
  end
end
