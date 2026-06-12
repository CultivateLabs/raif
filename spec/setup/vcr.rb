# frozen_string_literal: true

require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.ignore_localhost = true
  # config.debug_logger = $stdout

  # Never record AWS SSO / OIDC credential-resolution traffic. When recording Bedrock
  # cassettes via an SSO profile, the SDK resolves credentials over HTTP, and those
  # responses contain real access/refresh tokens and temporary credentials that must
  # not be written to a cassette. Ignored requests still hit the network (so credential
  # resolution works) but are never recorded.
  config.ignore_request do |request|
    host = URI(request.uri).host.to_s
    host.start_with?("oidc.") || host.include?(".sso.")
  end

  config.default_cassette_options = {
    match_requests_on: [
      :method,
      VCR.request_matchers.uri_without_params(*Rails.application.config.filter_parameters),
      :body
    ]
  }

  # Filter sensitive project IDs in response bodies
  config.filter_sensitive_data("<OPENAI_PROJECT_ID>") do |interaction|
    interaction.response.body[/proj_[\w\d]+/]
  end

  # Filter AWS credentials in JSON response bodies
  config.filter_sensitive_data("<AWS_ACCESS_KEY_ID>") do |interaction|
    if interaction.response.body&.include?("accessKeyId")
      interaction.response.body[/"accessKeyId":"([^"]+)"/, 1]
    end
  end

  config.filter_sensitive_data("<AWS_SECRET_ACCESS_KEY>") do |interaction|
    if interaction.response.body&.include?("secretAccessKey")
      interaction.response.body[/"secretAccessKey":"([^"]+)"/, 1]
    end
  end

  config.filter_sensitive_data("<AWS_SESSION_TOKEN>") do |interaction|
    if interaction.response.body&.include?("sessionToken")
      interaction.response.body[/"sessionToken":"([^"]+)"/, 1]
    end
  end

  # Filter Authorization headers
  config.filter_sensitive_data("<PLACEHOLDER_AUTHORIZATION>") do |interaction|
    next unless interaction.request.headers["Authorization"]

    interaction.request.headers["Authorization"][0]
  end

  # Filter Set-Cookie headers entirely
  config.filter_sensitive_data("<SET_COOKIE>") do |interaction|
    interaction.response.headers["Set-Cookie"]&.join("; ")
  end

  {
    "Amz-Sdk-Invocation-Id" => "<AMZ_SDK_INVOCATION_ID>",
    "X-Amz-Sso-Bearer-Token" => "<AMZ_SSO_BEARER_TOKEN>",
    "X-Amz-Security-Token" => "<AMZ_SECURITY_TOKEN>",
    "X-Amz-Content-Sha256" => "<AMZ_CONTENT_SHA256>",
    "X-Goog-Api-Key" => "<GOOGLE_API_KEY>"
  }.each do |key, value|
    config.filter_sensitive_data(value) do |interaction|
      interaction.request.headers[key]&.first
    end
  end

  {
    "Openai-Organization" => "<OPENAI_ORGANIZATION>",
    "X-Request-Id" => "<REQUEST_ID>",
    "Requestid" => "<REQUESTID>",
    "X-Amzn-Requestid" => "<AMZN_REQUESTID>"
  }.each do |key, value|
    config.filter_sensitive_data(value) do |interaction|
      interaction.response.headers[key]&.first
    end
  end

  # Normalize provider-generated ids (tool call ids, response ids, etc.) to stable
  # placeholders. We scrub BOTH request and response bodies so that an id the model
  # returns in one turn's response and the agent echoes back in the next turn's request
  # collapse to the same placeholder - otherwise the recorded request (real id) would
  # never match the replayed request (placeholder id from the scrubbed response).
  config.before_record do |interaction|
    [interaction.request.body, interaction.response.body].each do |body|
      next unless body

      # For anything with an underscore (e.g. resp_abc123), replace the value with a placeholder
      ["resp", "msg", "fc", "call", "ws", "toolu", "fp", "tooluse"].each do |prefix|
        body.gsub!(/#{prefix}_[\w\d]+/) do |match|
          match.end_with?("_id") ? match : "#{prefix}_abc123"
        end
      end

      # For anything with a dash (e.g. chatcmpl-abc123), replace the value with a placeholder
      ["chatcmpl", "gen"].each do |prefix|
        body.gsub!(/#{prefix}-[\w\d]+/) do
          "#{prefix}-abc123"
        end
      end
    end

    # Scrubbing changes the response body length. Keep Content-Length in sync, otherwise
    # strict clients (e.g. the AWS SDK for Bedrock) reject the replayed response as truncated.
    if interaction.response.body
      content_length_key = interaction.response.headers.keys.find { |k| k.casecmp?("Content-Length") }
      interaction.response.headers[content_length_key] = [interaction.response.body.bytesize.to_s] if content_length_key
    end
  end

  config.before_record do |interaction|
    interaction.request.headers.delete("X-Api-Key")
    interaction.response.headers.delete("Set-Cookie")
    interaction.response.headers.delete("Request-Id")
    interaction.response.headers.delete("Anthropic-Organization-Id")
  end

  # Filter Google responseId in response bodies
  config.filter_sensitive_data("<GOOGLE_RESPONSE_ID>") do |interaction|
    if interaction.response.body&.include?("responseId")
      interaction.response.body[/"responseId"\s*:\s*"([^"]+)"/, 1]
    end
  end

  config.filter_sensitive_data("<GOOGLE_THOUGHT_SIGNATURE>") do |interaction|
    if interaction.response.body&.include?("thoughtSignature")
      interaction.response.body[/"thoughtSignature"\s*:\s*"([^"]+)"/, 1]
    end
  end

  Rails.application.config.filter_parameters.each do |param|
    config.filter_sensitive_data("FILTERED_#{param.to_s.upcase}") do |interaction|
      uri = URI(interaction.request.uri)
      params = CGI.parse(uri.query || "")
      params[param.to_s]&.first
    end
  end
end
