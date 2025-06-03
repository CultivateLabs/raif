# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::OpenAiResponses, type: :model do
  let(:llm){ Raif.llm(:open_ai_responses_gpt_4o) }
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
          "id" => "resp_abc123",
          "object" => "response",
          "created_at" => 1748365161,
          "status" => "completed",
          "background" => false,
          "error" => nil,
          "incomplete_details" => nil,
          "instructions" => nil,
          "max_output_tokens" => nil,
          "model" => "gpt-4o",
          "output" => [
            {
              "id" => "msg_abc123",
              "type" => "message",
              "status" => "completed",
              "content" => [
                {
                  "type" => "output_text",
                  "annotations" => [],
                  "text" => "Response content"
                }
              ],
              "role" => "assistant"
            }
          ],
          "parallel_tool_calls" => true,
          "previous_response_id" => nil,
          "reasoning" => { "effort" => nil, "summary" => nil },
          "service_tier" => "default",
          "store" => true,
          "temperature" => 0.7,
          "text" => { "format" => { "type" => "text" } },
          "tool_choice" => "auto",
          "tools" => [],
          "top_p" => 1.0,
          "truncation" => "disabled",
          "usage" => {
            "input_tokens" => 5,
            "input_tokens_details" => { "cached_tokens" => 0 },
            "output_tokens" => 10,
            "output_tokens_details" => { "reasoning_tokens" => 0 },
            "total_tokens" => 15
          },
          "user" => nil,
          "metadata" => {}
        }
      end

      before do
        stubs.post("responses") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the OpenAI Responses API and processes the response" do
        model_completion = llm.chat(messages: [{ role: "user", content: "Hello" }], system_prompt: "You are a helpful assistant")

        expect(model_completion.raw_response).to eq("Response content")
        expect(model_completion.completion_tokens).to eq(10)
        expect(model_completion.prompt_tokens).to eq(5)
        expect(model_completion.total_tokens).to eq(15)
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
                "text" => "Response content"
              }
            ],
            "role" => "assistant"
          }
        ])
      end
    end

    context "when the response format is json" do
      let(:response_body) do
        {
          "id" => "resp_abc123",
          "object" => "response",
          "created_at" => 1748368556,
          "status" => "completed",
          "background" => false,
          "error" => nil,
          "incomplete_details" => nil,
          "instructions" => "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object. Return your response as json.", # rubocop:disable Layout/LineLength
          "max_output_tokens" => nil,
          "model" => "gpt-4.1-mini-2025-04-14",
          "output" => [{
            "id" => "msg_abc123",
            "type" => "message",
            "status" => "completed",
            "content" => [{
              "type" => "output_text",
              "annotations" => [],
              "text" => "{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}"
            }],
            "role" => "assistant"
          }],
          "parallel_tool_calls" => true,
          "previous_response_id" => nil,
          "reasoning" => { "effort" => nil, "summary" => nil },
          "service_tier" => "default",
          "store" => true,
          "temperature" => 0.7,
          "text" => { "format" => { "type" => "json_object" } },
          "tool_choice" => "auto",
          "tools" => [],
          "top_p" => 1.0,
          "truncation" => "disabled",
          "usage" => {
            "input_tokens" => 90,
            "input_tokens_details" => { "cached_tokens" => 0 },
            "output_tokens" => 21,
            "output_tokens_details" => { "reasoning_tokens" => 0 },
            "total_tokens" => 111
          },
          "user" => nil,
          "metadata" => {}
        }
      end

      before do
        stubs.post("responses") do |_env|
          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "makes a request to the OpenAI Responses API and processes the response" do
        messages = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hello! How can I assist you today?" },
          { role: "user", content: "Can you you tell me a joke? Respond in json." },
        ]

        system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object." # rubocop:disable Layout/LineLength

        model_completion = llm.chat(messages: messages, response_format: :json, system_prompt: system_prompt)

        expect(model_completion.raw_response).to eq("{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}")
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
            "text" => "{\n  \"joke\": \"Why don't scientists trust atoms? Because they make up everything!\"\n}"
          }],
          "role" => "assistant"
        }])
      end
    end

    context "when using developer-managed tools" do
      let(:response_body) do
        json_file = File.read(Raif::Engine.root.join("spec/fixtures/llm_responses/open_ai_responses/developer_managed_fetch_url.json"))
        JSON.parse(json_file)
      end

      before do
        stubs.post("responses") do |env|
          body = JSON.parse(env.body)

          expect(body["tools"]).to eq([{
            "type" => "function",
            "name" => "fetch_url",
            "description" => "Fetch a URL and return the page content as markdown",
            "parameters" => {
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

        expect(model_completion.raw_response).to eq(nil)
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::FetchUrl"])
        expect(model_completion.response_array).to eq([{
          "id" => "fc_68373cdaffc08198a0asdg39e96ef6d11043abf0eb2e6b9c6",
          "type" => "function_call",
          "status" => "completed",
          "arguments" => "{\"url\":\"https://www.wsj.com\"}",
          "call_id" => "call_MTzWbTQdadsg1i1oxb0v0kZgUF8",
          "name" => "fetch_url"
        }])

        expect(model_completion.response_tool_calls).to eq([{
          "name" => "fetch_url",
          "arguments" => { "url" => "https://www.wsj.com" }
        }])
      end
    end

    context "when using provider-managed tools" do
      let(:response_body) do
        json_file = File.read(Raif::Engine.root.join("spec/fixtures/llm_responses/open_ai_responses/provider_managed_web_search.json"))
        JSON.parse(json_file)
      end

      before do
        stubs.post("responses") do |env|
          body = JSON.parse(env.body)
          expect(body["tools"]).to eq([{ "type" => "web_search_preview" }])

          [200, { "Content-Type" => "application/json" }, response_body]
        end
      end

      it "extracts tool calls correctly" do
        model_completion = llm.chat(
          messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }],
          available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
        )

        expect(model_completion.raw_response).to eq("Ruby on Rails has seen significant advancements in recent years, with the release of version 8.0 in November 2024 marking a pivotal moment in its evolution. ([zircon.tech](https://zircon.tech/blog/ruby-on-rails-8-0-a-new-era-of-independent-development/?utm_source=openai))\n\n**Key Developments in Ruby on Rails 8.0:**\n\n1. **Independent Deployment Capabilities:**\n   Rails 8.0 empowers individual developers to manage the entire application lifecycle, including deployment and management, without relying on Platform-as-a-Service (PaaS) providers. This shift provides greater control and flexibility over application infrastructure. ([zircon.tech](https://zircon.tech/blog/ruby-on-rails-8-0-a-new-era-of-independent-development/?utm_source=openai))\n\n2. **Reduced External Dependencies:**\n   The framework has minimized reliance on external libraries, integrating essential features directly into Rails. This approach enhances performance, stability, and security by reducing potential vulnerabilities associated with third-party updates. ([21twelveinteractive.com](https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/?utm_source=openai))\n\n3. **Enhanced Background Processing and Caching:**\n   Rails 8.0 introduces improvements to background job processing and caching systems, optimizing concurrency and resource management. These enhancements lead to more efficient handling of tasks like email processing and data imports, resulting in faster and more scalable applications. ([21twelveinteractive.com](https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/?utm_source=openai))\n\n4. **Integrated Push Notifications Framework:**\n   A built-in push notifications system allows developers to send real-time updates to users without the need for third-party services. This feature simplifies the implementation of live updates and interactive features, enhancing user engagement. ([21twelveinteractive.com](https://www.21twelveinteractive.com/latest-features-and-updates-with-rails-8-0/?utm_source=openai))\n\n5. **Improved Front-End Integration:**\n   Rails 8.0 continues to support modern front-end technologies, including Hotwire, which comprises Turbo and Stimulus. These tools enable the development of interactive, real-time web applications with minimal JavaScript, streamlining the development process and improving user experience. ([thefinanceinsiders.com](https://thefinanceinsiders.com/ruby-on-rails-in-2025-a-look-at-the-future-of-full-stack-development/?utm_source=openai))\n\n6. **Asynchronous Query Loading:**\n   The introduction of asynchronous querying through Active Record allows multiple database queries to run in parallel. This feature significantly reduces response times, making Rails applications more efficient, especially for data-intensive tasks. ([hyscaler.com](https://hyscaler.com/insights/updates-in-ruby-on-rails-7/?utm_source=openai))\n\n7. **Enhanced Security Measures:**\n   Rails 8.0 includes improved protection against common web vulnerabilities, such as enhanced CSRF protection and better handling of sensitive data. The framework now provides more secure defaults and clearer guidance on security best practices. ([zircon.tech](https://zircon.tech/blog/ruby-on-rails-8-0-a-new-era-of-independent-development/?utm_source=openai))\n\nThese developments reflect Rails' commitment to evolving with the demands of modern web development, offering developers powerful tools to build efficient, secure, and scalable applications.") # rubocop:disable Layout/LineLength
        expect(model_completion.available_model_tools).to eq(["Raif::ModelTools::ProviderManaged::WebSearch"])
        expect(model_completion.response_array.map{|v| v["type"] }).to eq(["web_search_call", "message"])
      end
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
end
