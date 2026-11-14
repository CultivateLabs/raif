# frozen_string_literal: true

require "rails_helper"
require "ipaddr"

# Cassettes are committed to a public repository. The before_record hooks in spec/setup/vcr.rb
# scrub what we know about, and this spec catches whatever they miss: a new header, a page
# that prints the caller's address in its body, or a hand-edited cassette.
RSpec.describe "VCR cassettes" do
  # A trailing period ends a match only when a digit follows it, so "8.8.8.8." at the end of a
  # sentence is caught while a version string such as 0.25.0.0.1 is not.
  ipv4 = /(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?!\w|\.\d)/
  # Addresses that cannot identify the recording machine: private, loopback, link-local,
  # documentation, and reserved ranges.
  non_public = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24
    192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/3
  ].map { |range| IPAddr.new(range) }

  public_ipv4s = lambda do |text|
    # Bodies are mostly JSON, where an escape such as \n or \u003e can come right before an
    # address; its last character would fail the lookbehind, so replace escapes with a space.
    text.to_s.gsub(/\\(?:[nrtbf"\/\\]|u\h{4})/, " ").scan(ipv4).select do |candidate|
      address = IPAddr.new(candidate)
      non_public.none? { |range| range.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  cassettes = Dir[File.expand_path("../vcr_cassettes/**/*.yml", __dir__)]

  it "finds cassettes to check" do
    expect(cassettes).not_to be_empty
  end

  it "drops client IP headers from both sides before recording" do
    request = VCR::Request.new(:get, "https://example.com/", "", { "X-Forwarded-For" => ["198.51.100.7"], "Accept" => ["*/*"] })
    response = VCR::Response.new(
      VCR::ResponseStatus.new(200, "OK"),
      { "x-client-ip" => ["198.51.100.7"], "Cf-Connecting-Ip" => ["198.51.100.7"], "Content-Type" => ["text/html"] },
      "ok"
    )
    interaction = VCR::HTTPInteraction.new(request, response).hook_aware

    VCR.configuration.invoke_hook(:before_record, interaction, VCR::Cassette.new("vcr_cassettes_spec_hook_check"))

    expect(interaction.request.headers.keys).to eq(["Accept"])
    expect(interaction.response.headers.keys).to eq(["Content-Type"])
  end

  it "finds a public address that follows a JSON escape" do
    expect(public_ipv4s.call('{"a":"IP:\\n8.8.8.8","b":"<td\\u003e9.9.9.9"}')).to eq(%w[8.8.8.8 9.9.9.9])
  end

  cassettes.each do |path|
    name = path.delete_prefix("#{File.expand_path("../vcr_cassettes", __dir__)}/")

    it "#{name} records no client IP header or public IP address" do
      interactions = YAML.safe_load_file(path, permitted_classes: [Symbol, Time, Date], aliases: true).fetch("http_interactions", [])
      problems = []

      interactions.each_with_index do |interaction, index|
        %w[request response].each do |side|
          (interaction.dig(side, "headers") || {}).each do |header, values|
            if VCR_CLIENT_IP_HEADERS.any? { |ip_header| header.casecmp?(ip_header) }
              problems << "interaction #{index} #{side} header #{header}"
            end
            Array(values).each do |value|
              public_ipv4s.call(value).each { |ip| problems << "interaction #{index} #{side} header #{header}: #{ip}" }
            end
          end

          encoding = (interaction.dig(side, "headers") || {}).find { |header, _| header.casecmp?("Content-Encoding") }&.last
          encoding = Array(encoding).join(", ")
          if encoding.present? && !encoding.casecmp?("identity")
            problems << "interaction #{index} #{side} body is #{encoding}-encoded, so it cannot be scanned"
          end

          body = interaction.dig(side, "body") || {}
          text = body["string"] || body["base64_string"]&.unpack1("m")
          public_ipv4s.call(text).each do |ip|
            problems << "interaction #{index} #{side} body: #{ip}"
          end
        end
      end

      expect(problems).to be_empty, "Scrub these from #{name} (and add a filter in spec/setup/vcr.rb):\n#{problems.join("\n")}"
    end
  end
end
