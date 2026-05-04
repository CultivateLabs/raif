# frozen_string_literal: true

require "rails_helper"

# End-to-end regression test for the engine's prompt-template Mime registration.
#
# These specs hit a real controller in the dummy app to verify the negotiated
# format symbol can never be one of Raif's internal template formats,
# regardless of which content-type string the client sends.
RSpec.describe "Mime negotiation for HTTP requests", type: :request do
  HOSTILE_ACCEPT_HEADERS = [
    "text/plain",
    "application/x-raif-prompt",
    "application/x-raif-system-prompt",
  ].freeze

  HOSTILE_ACCEPT_HEADERS.each do |accept|
    it "does not resolve Accept: #{accept} to a Raif internal template format" do
      get "/agents", headers: { "Accept" => accept }

      expect(request.format.symbol).not_to eq(:prompt)
      expect(request.format.symbol).not_to eq(:system_prompt)
    end
  end
end
