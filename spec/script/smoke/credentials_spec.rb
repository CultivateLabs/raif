# frozen_string_literal: true

require "rails_helper"
require Raif::Engine.root.join("script/smoke/credentials")

RSpec.describe Smoke::Credentials do
  [:bedrock_grok_4_6, :bedrock_claude_5_sonnet].each do |key|
    context key.to_s do
      let(:entry){ Raif.model_manifest.llm_entries.find { |model| model.key == key } }

      it "runs with AWS credentials" do
        allow(described_class).to receive(:bedrock_credentials_present?).and_return(true)
        expect(described_class.missing_for?(entry.provider_name)).to be(false)
      end

      it "skips with AWS setup instructions when credentials are absent" do
        allow(described_class).to receive(:bedrock_credentials_present?).and_return(false)
        expect(described_class.missing_for?(entry.provider_name)).to be(true)
        expect(described_class.instructions_for(entry.provider_name)).to include("AWS_PROFILE", "AWS_REGION")
      end
    end
  end
end
