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

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the Anthropic API and processes the text response", vcr: { cassette_name: "anthropic/format_text" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant.")

        expect(model_completion.messages).to eq([{ "role" => "user", "content" => [{ "type" => "text", "text" => "Hello" }] }])
        expect(model_completion.raw_response).to eq("Hello! How are you doing today? Is there anything I can help you with?")
        expect(model_completion.completion_tokens).to eq(20)
        expect(model_completion.prompt_tokens).to eq(14)
        expect(model_completion.total_tokens).to eq(34)
        expect(model_completion.llm_model_key).to eq("anthropic_claude_3_5_haiku")
        expect(model_completion.model_api_name).to eq("claude-3-5-haiku-latest")
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.system_prompt).to eq("You are a helpful assistant.")
        expect(model_completion.response_id).to eq("msg_abc123")
        expect(model_completion.response_array).to eq([{
          "type" => "text",
          "text" => "Hello! How are you doing today? Is there anything I can help you with?"
        }])
      end
    end

    context "when the response format is JSON and model does not use json_response tool" do
      it "makes a request to the Anthropic API and processes the JSON response", vcr: { cassette_name: "anthropic/format_json" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Please give me a JSON object with a name and age. Don't include any other text in your response." }],
          system_prompt: "You are a helpful assistant.",
          response_format: :json
        )

        expect(model_completion.raw_response).to eq("{\n    \"name\": \"John Doe\",\n    \"age\": 35\n}")
        expect(model_completion.completion_tokens).to eq(23)
        expect(model_completion.prompt_tokens).to eq(35)
        expect(model_completion.total_tokens).to eq(58)
        expect(model_completion.llm_model_key).to eq("anthropic_claude_3_5_haiku")
        expect(model_completion.model_api_name).to eq("claude-3-5-haiku-latest")
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.response_id).to eq("msg_abc123")
        expect(model_completion.response_array).to eq([{ "type" => "text", "text" => "{\n    \"name\": \"John Doe\",\n    \"age\": 35\n}" }])
      end
    end

    context "when the response format is JSON and model uses json_response tool" do
      let(:test_task) { Raif::TestJsonTask.new(creator: FB.build(:raif_test_user)) }

      it "extracts JSON response from json_response tool call", vcr: { cassette_name: "anthropic/format_json_with_tool" } do
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

      it "extracts JSON from the json_response tool ignoring text content", vcr: { cassette_name: "anthropic/format_json_with_mixed_content" } do
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

      it "falls back to extracting text response when no json_response tool is found",
        vcr: { cassette_name: "anthropic/format_json_with_no_tool_use" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Tell me a joke" }],
          response_format: :json,
          source: test_task
        )

        expect(model_completion.raw_response).to eq("{\"joke\":\"Why did the chicken cross the road?\",\"answer\":\"To get to the other side!\"}")
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
        allow(llm).to receive(:connection).and_return(test_connection)

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
      it "extracts tool calls correctly", vcr: { cassette_name: "anthropic/format_json_with_developer_managed_tool" } do
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
      it "extracts tool calls correctly", vcr: { cassette_name: "anthropic/format_json_with_provider_managed_tool" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }],
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )

        expect(model_completion.raw_response).to eq("Based on the search results, here are the latest developments in Ruby on Rails:\n\n1. Recent Versions and Release Strategy\n\nRuby on Rails 8.0.0 was released on November 8, 2024, introducing fundamental shifts in Rails development that enable individual developers to host and manage their applications independently\n. \nStarting with version 7.2, each minor release now follows a fixed support schedule: 1 year for bug fixes and 2 years for security fixes\n.\n\n2. Technological Improvements\n\nWith the 7th version, Rails introduced Hotwire, which solved frontend development challenges and made Ruby on Rails a true full-stack framework. Developers can now build fast, interactive UIs while relying less on JavaScript\n.\n\n3. Community and Popularity\n\nRuby on Rails has experienced a resurgence in recent years. The Hired 2023 State of Software Engineers report found it was the most in-demand skill for software engineering roles, with Ruby on Rails proficiency resulting in 1.64 times more interviews\n.\n\n4. Key Trends in 2025\n- \nPerformance remains a key focus, with an exciting change being a major emphasis on SQLite databases. Previously seen as a lightweight database for prototyping, it's now receiving more attention\n\n\n- \nWhile no longer setting trends as it did in the 2000s, Rails continues to update and improve its best practices. It remains a solid choice for building scalable, high-quality applications without reinventing the wheel\n\n\n5. Ongoing Development\n\nThe resurgence has been significantly bolstered by innovations like Hotwire and improvements in JavaScript integration\n. \nThe framework continues to get stronger with regular updates, becoming faster, more secure, and better at working with modern frameworks\n.\n\nUnique Selling Points:\n- \nRails enables teams to rapidly develop innovative web apps, with a focus on speed of development. Development teams can produce more with the same or fewer resources\n\n- \nIt provides ready-to-use tools that help developers build websites and apps faster, allowing them to focus on creating great features\n\n\nThe framework remains popular among major companies, \nincluding Airbnb, Basecamp, GitHub, Hulu, and Shopify\n. \nIt continues to be a reliable and versatile choice for all kinds of projects, from startups to business expansions, providing tools and efficiency to help developers succeed\n.") # rubocop:disable Layout/LineLength
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
          "text",
          "text",
          "text",
          "text",
          "text",
          "text"
        ])

        # Test that citations are extracted from web search results
        expect(model_completion.citations).to eq([
          {
            "url" => "https://en.wikipedia.org/wiki/Ruby_on_Rails",
            "title" => "Ruby on Rails - Wikipedia"
          },
          {
            "url" => "https://endoflife.date/rails",
            "title" => "Ruby on Rails | endoflife.date"
          },
          {
            "url" => "https://rubyroidlabs.com/blog/2025/03/ror-trends/",
            "title" => "Ruby on Rails Trends 2025: Key Updates and Insights"
          },
          {
            "url" => "https://devops.com/the-ruby-on-rails-resurgence-2/",
            "title" => "Best of 2024: The Ruby on Rails Resurgence - DevOps.com"
          }
        ])
      end
    end

    context "streaming" do
      before do
        allow(Raif.config).to receive(:streaming_update_chunk_size_threshold).and_return(10)
      end

      it "streams a text response correctly", vcr: { cassette_name: "anthropic/streaming_text" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Hello" }]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("Hi there! How are you doing today? Is there anything I can help you with?")
        expect(model_completion.completion_tokens).to eq(21)
        expect(model_completion.prompt_tokens).to eq(8)
        expect(model_completion.total_tokens).to eq(29)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{ "role" => "user", "content" => [{ "type" => "text", "text" => "Hello" }] }])

        expect(deltas).to eq([
          "Hi there! How are you doing",
          " today? Is there anything I can help",
          " you with?"
        ])
      end

      it "streams a json response correctly", vcr: { cassette_name: "anthropic/streaming_json" } do
        system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key and a single `answer` key. Do not include any other text in your response outside the JSON object." # rubocop:disable Layout/LineLength

        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "Can you you tell me a joke? Respond in json." }],
          system_prompt: system_prompt,
          response_format: :json
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("{\n    \"joke\": \"Why don't scientists trust atoms?\",\n    \"answer\": \"Because they make up everything!\"\n}") # rubocop:disable Layout/LineLength
        expect(model_completion.parsed_response).to eq({
          "joke" => "Why don't scientists trust atoms?",
          "answer" => "Because they make up everything!"
        })
        expect(model_completion.completion_tokens).to eq(32)
        expect(model_completion.prompt_tokens).to eq(70)
        expect(model_completion.total_tokens).to eq(102)
        expect(model_completion).to be_persisted
        expect(model_completion.response_array).to eq([{
          "type" => "text",
          "text" => "{\n    \"joke\": \"Why don't scientists trust atoms?\",\n    \"answer\": \"Because they make up everything!\"\n}"
        }])

        expect(deltas).to eq([
          "{\n    \"joke\":",
          " \"Why don't scientists",
          " trust atoms?",
          "\",\n    \"answer",
          "\": \"Because they make",
          " up everything!\"\n}"
        ])
      end

      it "streams a response with tool calls correctly", vcr: { cassette_name: "anthropic/streaming_tool_calls" } do
        deltas = []
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        ) do |_model_completion, delta, _sse_event|
          deltas << delta
        end

        expect(model_completion.raw_response).to eq("I'll fetch the content of the Wall Street Journal homepage for you.")
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])

        expect(model_completion.response_tool_calls).to eq([{
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])

        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{
          "role" => "user",
          "content" => [{
            "type" => "text",
            "text" => "What's on the homepage of https://www.wsj.com today?"
          }]
        }])

        expect(deltas).to eq(["I'll fetch", " the content", " of the Wall", " Street Journal homepage for", " you."])
      end

      it "handles streaming errors", vcr: { cassette_name: "anthropic/streaming_error" } do
        expect do
          llm.chat(
            messages: [{ role: "user", content: "trigger error" }]
          ) do # empty block to trigger streaming
          end
        end.to raise_error(Raif::Errors::StreamingError) do |error|
          expect(error.message).to eq("Anthropic's API is temporarily overloaded. Please try again in a few minutes.")
          expect(error.type).to eq("overloaded_error")
          expect(error.event).to eq({
            "type" => "error",
            "error" => {
              "type" => "overloaded_error",
              "message" => "Anthropic's API is temporarily overloaded. Please try again in a few minutes."
            }
          })
        end
      end
    end

    context "error handling" do
      before do
        allow(llm).to receive(:connection).and_return(test_connection)
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

  describe "#extract_citations" do
    context "with citations in response" do
      it "extracts citations from text blocks with citations" do
        response_json = {
          "content" => [
            {
              "type" => "text",
              "text" => "Based on the search results, here are the latest AI developments.",
              "citations" => [
                {
                  "type" => "web_search_result_location",
                  "url" => "https://example.com/ai-news",
                  "title" => "Latest AI Developments",
                  "encrypted_index" => "abc123",
                  "cited_text" => "AI technology has advanced..."
                },
                {
                  "type" => "web_search_result_location",
                  "url" => "https://example.com/tech-news",
                  "title" => "Tech Industry News",
                  "encrypted_index" => "def456",
                  "cited_text" => "The tech industry is..."
                }
              ]
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)

        expect(citations).to contain_exactly(
          { "url" => "https://example.com/ai-news", "title" => "Latest AI Developments" },
          { "url" => "https://example.com/tech-news", "title" => "Tech Industry News" }
        )
      end

      it "removes duplicate citations by URL" do
        response_json = {
          "content" => [
            {
              "type" => "text",
              "text" => "First mention of the source.",
              "citations" => [
                {
                  "type" => "web_search_result_location",
                  "url" => "https://example.com/same-url",
                  "title" => "First Title"
                }
              ]
            },
            {
              "type" => "text",
              "text" => "Second mention of the same source.",
              "citations" => [
                {
                  "type" => "web_search_result_location",
                  "url" => "https://example.com/same-url",
                  "title" => "Second Title"
                }
              ]
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)

        expect(citations).to eq([
          { "url" => "https://example.com/same-url", "title" => "First Title" }
        ])
      end
    end

    context "without citations in response" do
      it "returns empty array when no content" do
        response_json = { "content" => nil }
        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end

      it "returns empty array when no citations in text blocks" do
        response_json = {
          "content" => [
            {
              "type" => "text",
              "text" => "Some response without citations"
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end

      it "ignores non-web_search_result_location citation types" do
        response_json = {
          "content" => [
            {
              "type" => "text",
              "text" => "Response with other citation types",
              "citations" => [
                {
                  "type" => "other_citation_type",
                  "url" => "https://example.com/ignored",
                  "title" => "Should be ignored"
                }
              ]
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end
    end
  end
end
