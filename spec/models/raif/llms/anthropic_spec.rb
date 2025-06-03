# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::Anthropic, type: :model do
  let(:llm){ Raif.llm(:anthropic_claude_3_5_haiku) }
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
          "id" => "msg_abc123",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-3-5-haiku-20241022",
          "content" => [{
            "type" => "text",
            "text" => "Hi there! How are you doing today? Is there anything I can help you with?"
          }],
          "stop_reason" => "end_turn",
          "stop_sequence" => nil,
          "usage" => {
            "input_tokens" => 8,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 21,
            "service_tier" => "standard"
          }
        }
      end

      before do
        stubs.post("messages") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the Anthropic API and processes the text response" do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")

        expect(model_completion.raw_response).to eq("Hi there! How are you doing today? Is there anything I can help you with?")
        expect(model_completion.completion_tokens).to eq(21)
        expect(model_completion.prompt_tokens).to eq(8)
        expect(model_completion.total_tokens).to eq(29)
        expect(model_completion.llm_model_key).to eq("anthropic_claude_3_5_haiku")
        expect(model_completion.model_api_name).to eq("claude-3-5-haiku-latest")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
        expect(model_completion.response_id).to eq("msg_abc123")
        expect(model_completion.response_array).to eq([{
          "type" => "text",
          "text" => "Hi there! How are you doing today? Is there anything I can help you with?"
        }])
      end
    end

    context "when the response format is JSON and model does not use json_response tool" do
      let(:response_body) do
        {
          "id" => "msg_abc123",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-3-5-haiku-20241022",
          "content" => [
            {
              "type" => "text",
              "text" => "{\n    \"name\": \"Emily Johnson\",\n    \"age\": 28\n}"
            }
          ],
          "stop_reason" => "end_turn",
          "stop_sequence" => nil,
          "usage" => {
            "input_tokens" => 35,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 22,
            "service_tier" => "standard"
          }
        }
      end

      before do
        stubs.post("messages") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the Anthropic API and processes the JSON response" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Please give me a JSON object with a name and age. Don't include any other text in your response." }],
          system_prompt: "You are a helpful assistant.",
          response_format: :json
        )

        expect(model_completion.raw_response).to eq("{\n    \"name\": \"Emily Johnson\",\n    \"age\": 28\n}")
        expect(model_completion.completion_tokens).to eq(22)
        expect(model_completion.prompt_tokens).to eq(35)
        expect(model_completion.total_tokens).to eq(57)
        expect(model_completion.llm_model_key).to eq("anthropic_claude_3_5_haiku")
        expect(model_completion.model_api_name).to eq("claude-3-5-haiku-latest")
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.response_id).to eq("msg_abc123")
        expect(model_completion.response_array).to eq([{ "type" => "text", "text" => "{\n    \"name\": \"Emily Johnson\",\n    \"age\": 28\n}" }])
      end
    end

    context "when the response format is JSON and model uses json_response tool" do
      let(:test_task) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      let(:response_body) do
        {
          "id" => "msg_abc123",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-3-5-haiku-20241022",
          "content" => [{
            "type" => "tool_use",
            "id" => "toolu_abc123",
            "name" => "json_response",
            "input" => {
              "joke" => "Why don't scientists trust atoms?",
              "answer" => "Because they make up everything!"
            }
          }],
          "stop_reason" => "tool_use",
          "stop_sequence" => nil,
          "usage" => {
            "input_tokens" => 371,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 80,
            "service_tier" => "standard"
          }
        }
      end

      before do
        stubs.post("messages") do |env|
          # Verify the json_response tool is included in the request
          body = JSON.parse(env.body)
          expect(body["tools"]).to include(
            hash_including(
              "name" => "json_response",
              "description" => "Generate a structured JSON response based on the provided schema."
            )
          )
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "extracts JSON response from json_response tool call" do
        model_completion = llm.chat(
          messages: [{
            role: "user",
            content: "Please give me a JSON object with a joke and answer. Don't include any other text in your response."
          }],
          response_format: :json,
          source: test_task
        )

        expected_json = JSON.generate({
          "joke" => "Why don't scientists trust atoms?",
          "answer" => "Because they make up everything!"
        })

        expect(model_completion.raw_response).to eq(expected_json)
        expect(model_completion.response_tool_calls).to eq([
          {
            "name" => "json_response",
            "arguments" => {
              "joke" => "Why don't scientists trust atoms?",
              "answer" => "Because they make up everything!"
            }
          }
        ])
        expect(model_completion.completion_tokens).to eq(80)
        expect(model_completion.prompt_tokens).to eq(371)
        expect(model_completion.total_tokens).to eq(451)
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.response_id).to eq("msg_abc123")
        expect(model_completion.response_array).to eq([{
          "id" => "toolu_abc123",
          "input" => {
            "answer" => "Because they make up everything!",
            "joke" => "Why don't scientists trust atoms?"
          },
          "name" => "json_response",
          "type" => "tool_use"
        }])
      end
    end

    context "when JSON response format is requested but model returns mixed content" do
      let(:test_task) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      let(:response_body) do
        {
          "content" => [
            { "type" => "text", "text" => "Here's the joke you requested:" },
            {
              "type" => "tool_use",
              "name" => "json_response",
              "input" => {
                "joke" => "What do you call a fish wearing a crown?",
                "answer" => "King Neptune!"
              }
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 20 }
        }
      end

      before do
        stubs.post("messages") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "extracts JSON from the json_response tool ignoring text content" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Tell me a joke" }],
          response_format: :json,
          source: test_task
        )

        expected_json = JSON.generate({
          "joke" => "What do you call a fish wearing a crown?",
          "answer" => "King Neptune!"
        })

        expect(model_completion.raw_response).to eq(expected_json)
        expect(model_completion.response_tool_calls).to include(
          hash_including(
            "name" => "json_response",
            "arguments" => hash_including("joke" => "What do you call a fish wearing a crown?")
          )
        )
      end
    end

    context "when JSON response format is requested but no json_response tool is used" do
      let(:test_task) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      let(:response_body) do
        {
          "content" => [
            { "type" => "text", "text" => "{\"joke\": \"Why did the chicken cross the road?\", \"answer\": \"To get to the other side!\"}" }
          ],
          "usage" => { "input_tokens" => 5, "output_tokens" => 8 }
        }
      end

      before do
        stubs.post("messages") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "falls back to extracting text response when no json_response tool is found" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Tell me a joke" }],
          response_format: :json,
          source: test_task
        )

        expect(model_completion.raw_response).to eq("{\"joke\": \"Why did the chicken cross the road?\", \"answer\": \"To get to the other side!\"}")
        expect(model_completion.response_tool_calls).to be_nil
      end
    end

    context "when JSON response format is requested but content is nil" do
      let(:response_body) do
        {
          "usage" => { "input_tokens" => 5, "output_tokens" => 0 }
        }
      end

      before do
        stubs.post("messages") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "returns nil when content is missing" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Hello" }],
          response_format: :json
        )

        expect(model_completion.raw_response).to be_nil
        expect(model_completion.response_tool_calls).to be_nil
      end
    end

    context "when using developer-managed tools" do
      let(:response_body) do
        json_file = File.read(Raif::Engine.root.join("spec/fixtures/llm_responses/anthropic/developer_managed_fetch_url.json"))
        JSON.parse(json_file)
      end

      before do
        stubs.post("messages") do |env|
          body = JSON.parse(env.body)
          expect(body["tools"]).to eq([{
            "name" => "fetch_url",
            "description" => "Fetch a URL and return the page content as markdown",
            "input_schema" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => { "url" => { "type" => "string", "description" => "The URL to fetch content from" } },
              "required" => ["url"]
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

        expect(model_completion.raw_response).to eq("I'll fetch the content of the Wall Street Journal homepage for you.")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([
          {
            "type" => "text",
            "text" => "I'll fetch the content of the Wall Street Journal homepage for you."
          },
          {
            "id" => "toolu_abc123",
            "input" => { "url" => "https://www.wsj.com" },
            "name" => "fetch_url",
            "type" => "tool_use"
          }
        ])

        expect(model_completion.response_tool_calls).to eq([
          {
            "name" => "fetch_url",
            "arguments" => { "url" => "https://www.wsj.com" }
          }
        ])
      end
    end

    context "when using provider-managed tools" do
      let(:response_body) do
        json_file = File.read(Raif::Engine.root.join("spec/fixtures/llm_responses/anthropic/provider_managed_web_search.json"))
        JSON.parse(json_file)
      end

      before do
        stubs.post("messages") do |env|
          body = JSON.parse(env.body)
          expect(body["tools"]).to eq([{
            "type" => "web_search_20250305",
            "name" => "web_search",
            "max_uses" => 5
          }])

          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "extracts tool calls correctly" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }],
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )

        expect(model_completion.raw_response).to eq("Based on the search results, here are the latest developments in Ruby on Rails:\n\n1. Recent Versions and Support\n\nThe latest update was Rails 7.0.5 in May 2023\n. However, \nmore recent versions include:\n- 7.2.0 (August 2024)\n- 8.0.0 (November 2024)\n\n\n2. Support Policy\n\nStarting with version 7.2, each minor release will be:\n- Supported for 1 year with bug fixes\n- Supported for 2 years with security fixes\n\n\n3. Notable Developments\n\nRuby on Rails has experienced a resurgence, with the Hired 2023 State of Software Engineers report finding it the most in-demand skill for software engineering roles. Proficiency in Ruby on Rails resulted in 1.64 times more interview opportunities.\n\n\n4. Key Innovations\n\nThe resurgence has been significantly bolstered by innovations like Hotwire and improvements in JavaScript integration\n. \nPrevious major updates (Rails 6.0) brought significant improvements, including:\n- Action Mailbox for handling incoming emails\n- Action Text for rich-text content and editing\n- Multiple database support\n- Parallel testing\n- Webpacker as the default JavaScript builder\n- Zeitwerk code loader\n\n\n5. Future Outlook\n\nRuby on Rails continues to provide a framework that enables faster development and speed to market. Development teams are increasingly looking for tools that help them produce more with the same or fewer resources, which is where Rails excels.\n\n\n6. Community and Adoption\n\nWell-known sites using Ruby on Rails include Airbnb, GitHub, Twitch, and Shopify\n. \nWhile it took a backseat to JavaScript in the late 2010s, many developers continued to use it to rapidly build API layers for JavaScript front-ends, largely because Rails makes development so simple.\n\n\nInteresting Perspective\n\nThe framework is gaining recognition not just for its technical capabilities, but also for improving developer happiness. As a free, open-source project, it enables teams to rapidly develop innovative web apps for clients who need quick deployment, potentially helping developers maintain a better work-life balance.") # rubocop:disable Layout/LineLength
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::ProviderManaged::WebSearch"])
        expect(model_completion.response_array.map{|v| v["type"] }).to eq([
          "server_tool_use",
          "web_search_tool_result",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text",
          "text"
        ])
      end
    end

    context "when the API returns a 400-level error" do
      let(:error_response_body) do
        <<~JSON
          {
            "error": {
              "message": "API rate limit exceeded",
              "type": "rate_limit_error"
            }
          }
        JSON
      end

      before do
        stubs.post("messages") do |_env|
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
            "type": "error",
            "error": {
              "type": "server_error",
              "message": "Internal server error"
            }
          }
        JSON
      end

      before do
        stubs.post("messages") do |_env|
          raise Faraday::ServerError.new(
            "Internal server error",
            { status: 500, body: error_response_body }
          )
        end

        allow(Raif.config).to receive(:llm_request_max_retries).and_return(0)
      end

      it "raises a Faraday::ServerError with the error message" do
        expect do
          llm.chat(message: "Hello")
        end.to raise_error(Faraday::ServerError)
      end
    end
  end

  describe "#build_tools_parameter" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "anthropic_claude_3_5_haiku",
        model_api_name: "claude-3-5-haiku-latest",
        available_model_tools: available_model_tools,
        response_format: response_format,
        source: source
      )
    end

    let(:response_format) { "text" }
    let(:source) { nil }

    context "with no tools and text response format" do
      let(:available_model_tools) { [] }

      it "returns an empty array" do
        result = llm.send(:build_tools_parameter, model_completion)
        expect(result).to eq([])
      end
    end

    context "with JSON response format and schema" do
      let(:available_model_tools) { [] }
      let(:response_format) { "json" }
      let(:source) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      it "includes json_response tool when JSON format is requested with schema" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq([{
          name: "json_response",
          description: "Generate a structured JSON response based on the provided schema.",
          input_schema: {
            type: "object",
            additionalProperties: false,
            required: ["joke", "answer"],
            properties: {
              joke: { type: "string" },
              answer: { type: "string" }
            }
          }
        }])
      end
    end

    context "with developer-managed tools" do
      let(:available_model_tools) { [Raif::TestModelTool] }

      it "formats developer-managed tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq([{
          name: "test_model_tool",
          description: "Mock Tool Description",
          input_schema: {
            type: "object",
            additionalProperties: false,
            required: ["items"],
            properties: {
              items: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  properties: {
                    title: { type: "string", description: "The title of the item" },
                    description: { type: "string" }
                  },
                  required: ["title", "description"]
                }
              }
            }
          }
        }])
      end
    end

    context "with provider-managed tools" do
      context "with WebSearch tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::WebSearch] }

        it "formats WebSearch tool correctly" do
          result = llm.send(:build_tools_parameter, model_completion)

          expect(result).to eq([{
            type: "web_search_20250305",
            name: "web_search",
            max_uses: 5
          }])
        end
      end

      context "with CodeExecution tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::CodeExecution] }

        it "formats CodeExecution tool correctly" do
          result = llm.send(:build_tools_parameter, model_completion)

          expect(result).to eq([{
            type: "code_execution_20250522",
            name: "code_execution"
          }])
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

    context "with mixed tool types and JSON response" do
      let(:available_model_tools) { [Raif::TestModelTool, Raif::ModelTools::ProviderManaged::WebSearch] }
      let(:response_format) { "json" }
      let(:source) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      it "includes json_response tool and formats all tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to contain_exactly(
          {
            name: "json_response",
            description: "Generate a structured JSON response based on the provided schema.",
            input_schema: {
              type: "object",
              additionalProperties: false,
              required: ["joke", "answer"],
              properties: {
                joke: { type: "string" },
                answer: { type: "string" }
              }
            }
          },
          {
            name: "test_model_tool",
            description: "Mock Tool Description",
            input_schema: {
              type: "object",
              additionalProperties: false,
              required: ["items"],
              properties: {
                items: {
                  type: "array",
                  items: {
                    type: "object",
                    additionalProperties: false,
                    properties: {
                      title: { type: "string", description: "The title of the item" },
                      description: { type: "string" }
                    },
                    required: ["title", "description"]
                  }
                }
              }
            }
          },
          {
            type: "web_search_20250305",
            name: "web_search",
            max_uses: 5
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
      expect(formatted_messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello", "type" => "text" }] }])
    end

    it "formats the messages correctly with an array as the content" do
      messages = [{ "role" => "user", "content" => ["Hello", "World"] }]
      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "content" => [
            { "type" => "text", "text" => "Hello" },
            { "type" => "text", "text" => "World" }
          ]
        }
      ])
    end

    it "formats the messages correctly with an image" do
      image_path = Raif::Engine.root.join("spec/fixtures/files/cultivate.png")
      image = Raif::ModelImageInput.new(input: image_path)
      messages = [{
        "role" => "user",
        "content" => [
          { "text" => "Hello" },
          image
        ]
      }]

      formatted_messages = llm.format_messages(messages)
      expect(formatted_messages).to eq([
        {
          "role" => "user",
          "content" => [
            { "text" => "Hello" },
            {
              "type" => "image",
              "source" => {
                "type" => "base64",
                "media_type" => "image/png",
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
          "content" => [
            {
              "type" => "image",
              "source" => {
                "type" => "url",
                "url" => image_url
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
          "content" => [
            { "type" => "text", "text" => "What's in this file?" },
            {
              "type" => "document",
              "source" => {
                "type" => "base64",
                "media_type" => "application/pdf",
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
          "content" => [
            {
              "type" => "document",
              "source" => {
                "type" => "url",
                "url" => file_url
              }
            }
          ]
        }
      ])
    end
  end
end
