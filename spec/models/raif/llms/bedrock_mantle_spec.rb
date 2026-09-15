# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Llms::BedrockMantle, type: :model do
  it_behaves_like "an LLM that uses OpenAI's Completions API message formatting"
  it_behaves_like "an LLM that uses OpenAI's Completions API tool formatting"

  let(:llm){ Raif.llm(:bedrock_grok_4_6) }
  let(:credentials){ Aws::Credentials.new("mantle-access-key", "mantle-secret-key", "mantle-session-token") }
  let(:url){ "https://bedrock-mantle.us-west-2.api.aws/openai/v1/chat/completions" }
  let(:response_body) do
    {
      id: "mantle-123",
      choices: [{ index: 0, message: { role: "assistant", content: "Hello" }, finish_reason: "stop" }],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
    }
  end

  before do
    allow(Raif.config).to receive_messages(
      llm_api_requests_enabled: true,
      aws_bedrock_region: "us-west-2",
      bedrock_mantle_base_url: "https://bedrock-mantle.us-west-2.api.aws/openai/v1"
    )
    allow(Aws::CredentialProviderChain).to receive(:new).and_return(double(resolve: credentials))
  end

  it "signs the transmitted JSON with AWS credentials and uses the unprefixed model ID" do
    request = stub_request(:post, url).with do |req|
      body = JSON.parse(req.body)
      expect(req.headers["Authorization"]).to start_with("AWS4-HMAC-SHA256 Credential=mantle-access-key/")
      expect(req.headers["Authorization"]).to include("/us-west-2/bedrock-mantle/aws4_request")
      expect(req.headers["X-Amz-Security-Token"]).to eq("mantle-session-token")
      expect(req.headers["X-Amz-Content-Sha256"]).to eq(Digest::SHA256.hexdigest(req.body))
      signature = Aws::Sigv4::Signer.new(service: "bedrock-mantle", region: "us-west-2", credentials: credentials).sign_request(
        http_method: "POST", url: req.uri.to_s, body: req.body,
        headers: { "Content-Type" => req.headers["Content-Type"], "X-Amz-Date" => req.headers["X-Amz-Date"] }
      )
      expect(req.headers["Authorization"]).to eq(signature.headers["authorization"])
      expect(body).to include("model" => "xai.grok-4.6", "max_tokens" => 123)
      expect(body["messages"].first).to eq("role" => "system", "content" => "Be helpful")
      true
    end.to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

    completion = llm.chat(message: "Hello", system_prompt: "Be helpful", max_completion_tokens: 123)

    expect(request).to have_been_requested.once
    expect(completion.reload.raw_response).to eq("Hello")
    expect(completion.response_id).to eq("mantle-123")
    expect(completion.total_tokens).to eq(15)
    expect(completion.completion_tokens).to eq(5)
  end

  it "fails locally when AWS credentials are absent" do
    allow(Aws::CredentialProviderChain).to receive(:new).and_return(double(resolve: nil))
    expect { llm.chat(message: "Hello") }.to raise_error(Aws::Errors::MissingCredentialsError)
    expect(WebMock).not_to have_requested(:post, url)
  end

  it "uses refreshed credentials on subsequent requests through the same connection" do
    provider = double("refreshing credentials", set?: true)
    refreshed = Aws::Credentials.new("refreshed-access-key", "refreshed-secret-key", "refreshed-session-token")
    allow(provider).to receive(:credentials).and_return(credentials)
    allow(Aws::CredentialProviderChain).to receive(:new).and_return(double(resolve: provider))
    request = stub_request(:post, url)
      .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

    llm.chat(message: "Hello")
    allow(provider).to receive(:credentials).and_return(refreshed)
    llm.chat(message: "Hello again")

    expect(request).to have_been_requested.twice
    expect(WebMock).to have_requested(:post, url).with { |req|
      req.headers["Authorization"].include?("Credential=refreshed-access-key/") &&
        req.headers["X-Amz-Security-Token"] == "refreshed-session-token"
    }.once
  end

  it "does not expose the direct xAI batch API" do
    expect(llm).not_to be_supports_batch_inference
    expect(llm).not_to respond_to(:submit_batch!)
  end

  it "enforces native JSON schemas and records the response format" do
    completion = Raif::ModelCompletion.new(
      llm_model_key: llm.key, model_api_name: llm.api_name, messages: [],
      response_format: :json, source: Raif::TestJsonTask.new
    )
    params = llm.send(:build_request_parameters, completion)
    expect(params.dig(:response_format, :json_schema, :strict)).to be(true)
    expect(params.dig(:response_format, :json_schema, :schema)).to eq(completion.json_response_schema)
    expect(completion.response_format_parameter).to eq("json_schema")
  end

  it "streams content and usage through the shared Chat Completions parser" do
    chunks = [
      { id: "mantle-stream", choices: [{ index: 0, delta: { role: "assistant", content: "Hello" }, finish_reason: nil }] },
      { id: "mantle-stream", choices: [{ index: 0, delta: {}, finish_reason: "stop" }] },
      { id: "mantle-stream", choices: [], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }
    ]
    body = chunks.map { |chunk| "data: #{chunk.to_json}\n\n" }.join + "data: [DONE]\n\n"
    stub_request(:post, url).with { |req|
      JSON.parse(req.body)["stream"] == true && req.headers["Authorization"].start_with?("AWS4-HMAC-SHA256 ")
    }
      .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

    deltas = []
    completion = llm.chat(message: "Hello") { |_mc, delta, _event| deltas << delta }

    expect(deltas.join).to eq("Hello")
    expect(completion.reload.raw_response).to eq("Hello")
    expect(completion.total_tokens).to eq(15)
  end
end
