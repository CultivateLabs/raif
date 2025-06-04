# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::OpenAiResponses, type: :model do
  let(:llm){ Raif.llm(:open_ai_responses_gpt_4o) }

  describe "#chat" do
    context "when the response format is text" do
      it "makes a request to the OpenAI Responses API and processes the response", vcr: { cassette_name: "open_ai_responses/format_text" } do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant")

        expect(model_completion.raw_response).to eq("Hi there! How can I assist you today?")
        expect(model_completion.completion_tokens).to eq(11)
        expect(model_completion.prompt_tokens).to eq(17)
        expect(model_completion.total_tokens).to eq(28)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([{ "role" => "user", "content" => [{ "text" => "Hello", "type" => "input_text" }] }])
        expect(model_completion.system_prompt).to eq("You are a helpful assistant")
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.max_completion_tokens).to eq(nil)
        expect(model_completion.response_format).to eq("text")
        expect(model_completion.source).to be_nil
        expect(model_completion.llm_model_key).to eq("open_ai_responses_gpt_4o")
        expect(model_completion.model_api_name).to eq("gpt-4o")
        expect(model_completion.response_format_parameter).to be_nil
        expect(model_completion.response_id).to eq("resp_abc123")
        expect(model_completion.response_array).to eq([
          {
            "id" => "msg_abc123",
            "type" => "message",
            "status" => "completed",
            "content" => [
              {
                "type" => "output_text",
                "annotations" => [],
                "text" => "Hi there! How can I assist you today?"
              }
            ],
            "role" => "assistant"
          }
        ])
      end
    end

    context "when the response format is json" do
      it "makes a request to the OpenAI Responses API and processes the response", vcr: { cassette_name: "open_ai_responses/format_json" } do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hello! How can I assist you today?" },
          { role: "user", content: "Can you you tell me a joke? Respond in json." },
        ]

        system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object." # rubocop:disable Layout/LineLength

        model_completion = llm.chat(messages: messages, response_format: :json, system_prompt: system_prompt)

        expect(model_completion.raw_response).to eq("{\n    \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}")
        expect(model_completion.parsed_response).to eq({ "joke" => "Why don't scientists trust atoms? Because they make up everything!" })
        expect(model_completion.completion_tokens).to eq(21)
        expect(model_completion.prompt_tokens).to eq(90)
        expect(model_completion.total_tokens).to eq(111)
        expect(model_completion).to be_persisted
        expect(model_completion.messages).to eq([
          { "role" => "user", "content" => [{ "text" => "Hello", "type" => "input_text" }] },
          { "role" => "assistant", "content" => [{ "text" => "Hello! How can I assist you today?", "type" => "output_text" }] },
          { "role" => "user", "content" => [{ "text" => "Can you you tell me a joke? Respond in json.", "type" => "input_text" }] }
        ])
        expect(model_completion.system_prompt).to eq(system_prompt)
        expect(model_completion.temperature).to eq(0.7)
        expect(model_completion.max_completion_tokens).to eq(nil)
        expect(model_completion.response_format).to eq("json")
        expect(model_completion.source).to be_nil
        expect(model_completion.llm_model_key).to eq("open_ai_responses_gpt_4o")
        expect(model_completion.model_api_name).to eq("gpt-4o")
        expect(model_completion.response_format_parameter).to eq("json_object")
        expect(model_completion.response_id).to eq("resp_abc123")
        expect(model_completion.response_array).to eq([{
          "id" => "msg_abc123",
          "type" => "message",
          "status" => "completed",
          "content" => [{
            "type" => "output_text",
            "annotations" => [],
            "text" => "{\n    \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}"
          }],
          "role" => "assistant"
        }])
      end
    end

    context "when using developer-managed tools" do
      it "extracts tool calls correctly", vcr: { cassette_name: "open_ai_responses/developer_managed_fetch_url" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What's on the homepage of https://www.wsj.com today?" }],
          available_model_tools: [Raif::ModelTools::FetchUrl]
        )

        expect(model_completion.raw_response).to eq(nil)
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([{
          "id" => "fc_abc123",
          "type" => "function_call",
          "status" => "completed",
          "arguments" => "{\"url\":\"https://www.wsj.com\"}",
          "call_id" => "call_abc123",
          "name" => "fetch_url"
        }])

        expect(model_completion.response_tool_calls).to eq([{
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])
      end
    end

    context "when using provider-managed tools" do
      it "extracts tool calls correctly", vcr: { cassette_name: "open_ai_responses/provider_managed_web_search" } do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }],
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )

        expect(model_completion.raw_response).to eq("As of June 2025, Ruby on Rails (Rails) has introduced several significant updates and features aimed at enhancing developer productivity, application performance, and deployment flexibility.\n\n**Rails 8.0 Release**\n\nReleased on November 7, 2024, Rails 8.0 marks a pivotal shift in the framework's evolution. This version emphasizes empowering individual developers to manage application deployment and maintenance independently, reducing reliance on Platform-as-a-Service (PaaS) providers. Key enhancements include:\n\n- **Integrated Deployment Tools**: Rails 8.0 introduces built-in deployment solutions that seamlessly integrate with popular cloud providers. This allows developers to deploy applications with minimal configuration, streamlining the transition from development to production environments. ([zircon.tech](https://zircon.tech/blog/ruby-on-rails-8-0-a-new-era-of-independent-development/?utm_source=openai))\n\n- **Reduced External Dependencies**: By minimizing reliance on third-party libraries, Rails 8.0 offers faster, more stable applications with fewer security vulnerabilities. Essential features are now integrated directly into the framework, enhancing performance and simplifying maintenance. ([21twelveinteractive.com](https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/?utm_source=openai))\n\n- **Enhanced Background Processing and Caching**: The new background worker system is optimized for concurrency, enabling applications to handle multiple tasks simultaneously. Additionally, the improved caching system reduces database query frequency, leading to better load times and user experiences. ([21twelveinteractive.com](https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/?utm_source=openai))\n\n- **Push Notifications Framework**: Rails 8.0 introduces a built-in push notifications framework, simplifying the process of sending real-time updates to users without the need for third-party services. ([21twelveinteractive.com](https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/?utm_source=openai))\n\n**Rails 7.x Enhancements**\n\nPrior to the 8.0 release, Rails 7.x versions brought notable improvements:\n\n- **Hotwire Integration**: Rails 7 introduced Hotwire, comprising Turbo and Stimulus, to facilitate building reactive and real-time features with minimal JavaScript. Turbo Streams and Turbo Frames allow for dynamic content updates without full page reloads. ([hyscaler.com](https://hyscaler.com/insights/updates-in-ruby-on-rails-7/?utm_source=openai))\n\n- **JavaScript Modernization**: The framework moved away from Webpacker, adopting lightweight options like Importmaps, esbuild, and rollup for managing JavaScript assets, thereby simplifying frontend development. ([hyscaler.com](https://hyscaler.com/insights/updates-in-ruby-on-rails-7/?utm_source=openai))\n\n- **Asynchronous Query Loading**: Active Record now supports asynchronous querying, allowing multiple database queries to run in parallel, which is beneficial for data-intensive applications. ([hyscaler.com](https://hyscaler.com/insights/updates-in-ruby-on-rails-7/?utm_source=openai))\n\n- **Encrypted Attributes**: Rails 7 introduced built-in support for encrypted attributes, enabling developers to store sensitive data securely and comply with data protection regulations. ([hyscaler.com](https://hyscaler.com/insights/updates-in-ruby-on-rails-7/?utm_source=openai))\n\n**Community and Ecosystem Developments**\n\nThe Rails community continues to thrive, with ongoing contributions and events:\n\n- **Rails World 2025**: The Call for Papers for Rails World 2025 is open, inviting talks that highlight the framework's power and competitive advantage. ([rubyonrails.org](https://rubyonrails.org/blog/?utm_source=openai))\n\n- **Continuous Integration Enhancements**: Recent updates include the introduction of `bin/ci` to standardize continuous integration workflows, improving testing and deployment processes. ([rubyonrails.org](https://rubyonrails.org/blog/?utm_source=openai))\n\nThese developments reflect Rails' commitment to evolving with modern web development needs, focusing on developer empowerment, performance optimization, and streamlined deployment processes.") # rubocop:disable Layout/LineLength
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::ProviderManaged::WebSearch"])
        expect(model_completion.response_array.map{|v| v["type"] }).to eq(["web_search_call", "message"])

        # Test that citations are extracted from web search results
        expect(model_completion.citations).to eq([
          {
            "url" => "https://zircon.tech/blog/ruby-on-rails-8-0-a-new-era-of-independent-development/",
            "title" => "Ruby on Rails 8.0: A New Era of Independent Development"
          },
          {
            "url" => "https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/",
            "title" => "Exploring Rails 8.0: Latest Features and Updates"
          },
          {
            "url" => "https://hyscaler.com/insights/updates-in-ruby-on-rails-7/",
            "title" => "Exciting Updates in Ruby on Rails 7"
          },
          {
            "url" => "https://rubyonrails.org/blog/",
            "title" => "Ruby on Rails — News"
          }
        ])
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
                "type": "rate_limit_error",
                "param": null,
                "code": null
              }
            }
          JSON
        end

        before do
          stubs.post("responses") do |_env|
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
                "type": "server_error",
                "param": null,
                "code": null
              }
            }
          JSON
        end

        before do
          stubs.post("responses") do |_env|
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
          llm_model_key: "open_ai_responses_gpt_4o",
          model_api_name: "gpt-4o",
          temperature: 0.8,
          response_format: "text",
          system_prompt: system_prompt
        )
      end

      context "with system prompt" do
        let(:system_prompt) { "You are a helpful assistant" }

        it "includes instructions (system prompt) in the parameters" do
          expect(parameters[:model]).to eq("gpt-4o")
          expect(parameters[:temperature]).to eq(0.8)
          expect(parameters[:input]).to eq([{ "role" => "user", "content" => "Hello" }])
          expect(parameters[:instructions]).to eq("You are a helpful assistant")
          expect(parameters[:response_format]).to be_nil
        end
      end

      context "without system prompt" do
        let(:system_prompt) { nil }

        it "builds parameters without instructions" do
          expect(parameters[:model]).to eq("gpt-4o")
          expect(parameters[:temperature]).to eq(0.8)
          expect(parameters[:input]).to eq([{ "role" => "user", "content" => "Hello" }])
          expect(parameters[:instructions]).to be_nil
        end
      end
    end

    context "for JSON response format" do
      let(:system_prompt) { "You are a helpful assistant" }
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          system_prompt: system_prompt,
          llm_model_key: "open_ai_responses_gpt_4o",
          model_api_name: "gpt-4o",
          temperature: 0.5,
          response_format: "json"
        )
      end

      context "with existing system prompt" do
        it "appends 'Return your response as json.' to the system prompt" do
          expect(parameters[:instructions]).to eq("You are a helpful assistant. Return your response as JSON.")
        end
      end

      context "with no existing system prompt" do
        let(:system_prompt) { nil }

        it "Sets the instructions to 'Return your response as JSON.'" do
          expect(parameters[:instructions]).to eq("Return your response as JSON.")
        end
      end

      context "when the model completion has a json_response_schema" do
        before do
          model_completion.source = Raif::TestJsonTask.new
        end

        it "sets the response_format to json_schema" do
          expect(parameters[:text]).to eq({
            format: {
              type: "json_schema",
              name: "json_response_schema",
              strict: true,
              schema: {
                type: "object",
                additionalProperties: false,
                required: ["joke", "answer"],
                properties: {
                  joke: { type: "string" },
                  answer: { type: "string" }
                }
              }
            }
          })
        end
      end

      context "when the model completion does not have a json_response_schema" do
        it "sets the response_format to json_object" do
          expect(model_completion.json_response_schema).to be_nil
          expect(parameters[:text]).to eq({ format: { type: "json_object" } })
        end
      end
    end

    context "with max_completion_tokens" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "open_ai_responses_gpt_4o",
          model_api_name: "gpt-4o",
          temperature: 0.8,
          response_format: "text",
          max_completion_tokens: 1000
        )
      end

      it "includes max_output_tokens in the parameters" do
        expect(parameters[:max_output_tokens]).to eq(1000)
      end
    end

    context "with tools" do
      let(:model_completion) do
        mc = Raif::ModelCompletion.new(
          messages: [{ role: "user", content: "Hello" }],
          llm_model_key: "open_ai_responses_gpt_4o",
          model_api_name: "gpt-4o",
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
          type: "function",
          name: "test_model_tool",
          description: "Mock Tool Description",
          parameters: {
            type: "object",
            additionalProperties: false,
            required: ["items"],
            properties: {
              items: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["title", "description"],
                  properties: {
                    title: {
                      type: "string",
                      description: "The title of the item"
                    },
                    description: {
                      type: "string"
                    }
                  }
                }
              }
            }
          }
        })
      end
    end
  end

  describe "#build_tools_parameter" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "open_ai_responses_gpt_4o",
        model_api_name: "gpt-4o",
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
          type: "function",
          name: "test_model_tool",
          description: "Mock Tool Description",
          parameters: {
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
            type: "web_search_preview"
          }])
        end
      end

      context "with CodeExecution tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::CodeExecution] }

        it "formats CodeExecution tool correctly" do
          result = llm.send(:build_tools_parameter, model_completion)

          expect(result).to eq([{
            type: "code_interpreter",
            container: { "type": "auto" }
          }])
        end
      end

      context "with ImageGeneration tool" do
        let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::ImageGeneration] }

        it "formats ImageGeneration tool correctly" do
          result = llm.send(:build_tools_parameter, model_completion)

          expect(result).to eq([{
            type: "image_generation"
          }])
        end
      end
    end
  end

  describe "#determine_response_format" do
    context "with text response format" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          response_format: "text",
          llm_model_key: "open_ai_responses_gpt_4o"
        )
      end

      it "returns nil" do
        expect(llm.send(:determine_response_format, model_completion)).to be_nil
      end
    end

    context "with json response format but no json_response_schema" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          response_format: "json",
          llm_model_key: "open_ai_responses_gpt_4o",
          model_api_name: "gpt-4o"
        )
      end

      it "returns the default json_object format" do
        expect(model_completion.json_response_schema).to eq(nil)
        expect(llm.send(:determine_response_format, model_completion)).to eq({ type: "json_object" })
      end
    end

    context "with json response format and a model that doesn't support structured outputs" do
      let(:model_completion) do
        Raif::ModelCompletion.new(
          response_format: "json",
          llm_model_key: "open_ai_responses_gpt_3_5_turbo",
          model_api_name: "gpt-3.5-turbo"
        )
      end

      it "returns json_object type when structured outputs are not supported" do
        llm = Raif.llm(:open_ai_responses_gpt_3_5_turbo)
        result = llm.send(:determine_response_format, model_completion)
        expect(result).to eq({ type: "json_object" })
      end
    end

    context "with json format and source with json_response_schema" do
      let(:schema) do
        {
          type: "object",
          additionalProperties: false,
          required: ["result"],
          properties: {
            result: { type: "string" }
          }
        }
      end

      let(:source) do
        double("Source").tap do |s|
          allow(s).to receive(:respond_to?).with(:json_response_schema).and_return(true)
          allow(s).to receive(:json_response_schema).and_return(schema)
        end
      end

      let(:model_completion) do
        mc = Raif::ModelCompletion.new(
          response_format: "json",
          llm_model_key: "open_ai_responses_gpt_4o",
          model_api_name: "gpt-4o"
        )
        allow(mc).to receive(:source).and_return(source)
        mc
      end

      it "returns json_schema format with schema" do
        result = llm.send(:determine_response_format, model_completion)
        expect(result).to eq({
          type: "json_schema",
          name: "json_response_schema",
          strict: true,
          schema: schema
        })
      end
    end
  end

  describe "#extract_response_tool_calls" do
    context "when response has no output" do
      let(:response) { { "output" => nil } }

      it "returns nil" do
        expect(llm.send(:extract_response_tool_calls, response)).to be_nil
      end
    end

    context "when response has empty output" do
      let(:response) { { "output" => [] } }

      it "returns nil" do
        expect(llm.send(:extract_response_tool_calls, response)).to be_nil
      end
    end

    context "when response has only message outputs" do
      let(:response) do
        {
          "output" => [
            {
              "type" => "message",
              "content" => [{ "type" => "output_text", "text" => "Hello" }]
            }
          ]
        }
      end

      it "returns nil" do
        expect(llm.send(:extract_response_tool_calls, response)).to be_nil
      end
    end
  end

  describe "#extract_raw_response" do
    context "when response has no output" do
      let(:response) { { "output" => nil } }

      it "returns nil" do
        expect(llm.send(:extract_raw_response, response)).to be_nil
      end
    end

    context "when response has empty output" do
      let(:response) { { "output" => [] } }

      it "returns nil" do
        expect(llm.send(:extract_raw_response, response)).to be_nil
      end
    end

    context "when response has only function calls" do
      let(:response) do
        {
          "output" => [
            {
              "type" => "function_call",
              "name" => "get_weather",
              "arguments" => { "location" => "San Francisco" }
            }
          ]
        }
      end

      it "returns nil" do
        expect(llm.send(:extract_raw_response, response)).to be_nil
      end
    end

    context "when response has message outputs" do
      let(:response) do
        {
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "Hello" },
                { "type" => "output_text", "text" => "World" }
              ]
            }
          ]
        }
      end

      it "extracts and joins text content" do
        result = llm.send(:extract_raw_response, response)
        expect(result).to eq("Hello\nWorld")
      end
    end

    context "when response has multiple message outputs" do
      let(:response) do
        {
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "First message" }
              ]
            },
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "Second message" }
              ]
            }
          ]
        }
      end

      it "extracts and joins text from all messages" do
        result = llm.send(:extract_raw_response, response)
        expect(result).to eq("First message\nSecond message")
      end
    end

    context "when response has mixed content types" do
      let(:response) do
        {
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "Text content" },
                { "type" => "image", "url" => "http://example.com/image.jpg" }
              ]
            }
          ]
        }
      end

      it "only extracts text content" do
        result = llm.send(:extract_raw_response, response)
        expect(result).to eq("Text content")
      end
    end
  end

  describe "#extract_citations" do
    context "with citations in response" do
      it "extracts citations from message output annotations" do
        response_json = {
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "Based on recent news, here are the latest AI developments.",
                  "annotations" => [
                    {
                      "type" => "url_citation",
                      "url" => "https://example.com/ai-news",
                      "title" => "Latest AI Developments"
                    },
                    {
                      "type" => "url_citation",
                      "url" => "https://example.com/tech-news",
                      "title" => "Tech Industry News"
                    }
                  ]
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
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "First mention.",
                  "annotations" => [
                    {
                      "type" => "url_citation",
                      "url" => "https://example.com/same-url",
                      "title" => "First Title"
                    }
                  ]
                }
              ]
            },
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "Second mention.",
                  "annotations" => [
                    {
                      "type" => "url_citation",
                      "url" => "https://example.com/same-url",
                      "title" => "Second Title"
                    }
                  ]
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
      it "returns empty array when no output" do
        response_json = { "output" => nil }
        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end

      it "returns empty array when no annotations in messages" do
        response_json = {
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "Some response without citations"
                }
              ]
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end

      it "ignores non-url_citation annotation types" do
        response_json = {
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "Response with other annotation types",
                  "annotations" => [
                    {
                      "type" => "other_annotation_type",
                      "url" => "https://example.com/ignored",
                      "title" => "Should be ignored"
                    }
                  ]
                }
              ]
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end

      it "ignores non-message output types" do
        response_json = {
          "output" => [
            {
              "type" => "function_call",
              "name" => "some_function",
              "arguments" => "{}"
            }
          ]
        }

        citations = llm.send(:extract_citations, response_json)
        expect(citations).to eq([])
      end
    end
  end
end
