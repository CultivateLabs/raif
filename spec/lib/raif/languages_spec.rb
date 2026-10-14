# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif do
  describe ".supported_language_key?" do
    it "accepts a supported language with or without a region" do
      expect(%w[en en_gb en-GB EN_GB es-419 pt_BR].map { |key| Raif.supported_language_key?(key) }).to all(eq(true))
    end

    it "rejects an unsupported language, a malformed region, and a blank key" do
      expect(["xx", "xx_gb", "en_", "en_gbr", "en-GB-x-private", "", nil].map { |key| Raif.supported_language_key?(key) }).to all(eq(false))
    end
  end

  describe ".language_name" do
    it "names a base language" do
      expect(Raif.language_name("es")).to eq("Spanish")
    end

    it "names Norwegian" do
      expect(Raif.language_name("no")).to eq("Norwegian")
    end

    it "names a regional variant with a name of its own, whatever its separator and case" do
      expect(%w[en_gb en-GB EN_gb].map { |key| Raif.language_name(key) }).to all(eq("British English"))
    end

    it "adds the region to the base name when the variant has no name of its own" do
      expect(Raif.language_name("en_nz")).to eq("English (NZ)")
      expect(Raif.language_name("es-419")).to eq("Spanish (419)")
    end

    it "returns nil for an unsupported key" do
      expect(Raif.language_name("xx_gb")).to be_nil
    end
  end
end
