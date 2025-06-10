# frozen_string_literal: true

require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.ignore_localhost = true

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

  # Filter Authorization headers
  config.filter_sensitive_data("<PLACEHOLDER_AUTHORIZATION>") do |interaction|
    next unless interaction.request.headers["Authorization"]

    interaction.request.headers["Authorization"][0]
  end

  # Filter Set-Cookie headers entirely
  config.filter_sensitive_data("<SET_COOKIE>") do |interaction|
    interaction.response.headers["Set-Cookie"]&.join("; ")
  end

  # Filter OpenAI Organization header
  config.filter_sensitive_data("<OPENAI_ORGANIZATION>") do |interaction|
    interaction.response.headers["Openai-Organization"]&.first
  end

  # Filter Request and Response IDs
  config.filter_sensitive_data("<REQUEST_ID>") do |interaction|
    interaction.response.headers["X-Request-Id"]&.first
  end

  config.before_record do |interaction|
    if interaction.response.body
      # For anything with an underscore (e.g. resp_abc123), replace the value with a placeholder
      ["resp", "msg", "fc", "call", "ws", "toolu", "fp"].each do |prefix|
        interaction.response.body.gsub!(/#{prefix}_[\w\d]+/) do |match|
          match.end_with?("_id") ? match : "#{prefix}_abc123"
        end
      end

      # For anything with a dash (e.g. chatcmpl-abc123), replace the value with a placeholder
      ["chatcmpl", "gen"].each do |prefix|
        interaction.response.body.gsub!(/#{prefix}-[\w\d]+/) do
          "#{prefix}-abc123"
        end
      end
    end
  end

  config.before_record do |interaction|
    interaction.request.headers.delete("X-Api-Key")
    interaction.response.headers.delete("Set-Cookie")
    interaction.response.headers.delete("Request-Id")
    interaction.response.headers.delete("Anthropic-Organization-Id")
  end

  Rails.application.config.filter_parameters.each do |param|
    config.filter_sensitive_data("FILTERED_#{param.to_s.upcase}") do |interaction|
      uri = URI(interaction.request.uri)
      params = CGI.parse(uri.query || "")
      params[param.to_s]&.first
    end
  end
end
