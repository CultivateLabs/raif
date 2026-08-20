# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"

RSpec.describe "model_manifest validity" do
  manifest = Raif::ModelManifest.load
  entries = manifest.llm_entries
  all_keys = entries.map(&:key)

  it "has unique keys" do
    expect(all_keys).to eq(all_keys.uniq)
  end

  entries.each do |entry|
    describe entry.key.to_s do
      it "prefixes the key with its provider" do
        prefix = if entry.provider_name == "open_ai"
          Raif::ModelManifest::OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch(entry.endpoint)
        else
          "#{entry.provider_name}_"
        end
        expect(entry.key.to_s).to start_with(prefix)
      end

      it "has required fields" do
        expect(entry.api_name).to be_present
        expect(entry.display_name).to be_present
        expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.status)
      end

      it "has exactly the known capability keys" do
        expect(entry.capabilities.keys.sort).to eq(Raif::ModelManifest::CAPABILITY_KEYS.sort)
        entry.capabilities.except("provider_managed_tools").each_value do |v|
          expect([true, false]).to include(v)
        end
        expect(entry.capabilities["provider_managed_tools"] - Raif::ModelManifest::PROVIDER_MANAGED_TOOL_CLASSES.keys).to be_empty
      end

      it "has pricing unless retired" do
        next if entry.retired?

        # Float, not Integer: RegistryData and the generator divide this by 1_000_000, and
        # an Integer would silently floor the result to 0.
        expect(entry.pricing["input_per_million"]).to be_a(Float)
        expect(entry.pricing["output_per_million"]).to be_a(Float)
      end

      it "has coherent lifecycle fields" do
        if entry.deprecated?
          expect(entry.lifecycle["retirement_date"]).to be_present
        end

        replacement = entry.lifecycle["replacement_key"]
        if replacement
          target = entries.find { |e| e.key.to_s == replacement.to_s }
          expect(target).to be_present, "replacement_key #{replacement} not found in manifest"
          expect(target).to be_active, "replacement for a deprecated model must be active" if entry.deprecated?
        end
      end

      it "has well-formed verification records when present" do
        results = entry.verification&.dig("results") || {}
        expect(results.keys - entry.smokable_capabilities).to be_empty
        results.each_value do |record|
          expect(record).to include("claimed", "result", "checked_at")
        end
      end
    end
  end

  manifest.embedding_entries.each do |entry|
    describe entry.key.to_s do
      it "has required fields" do
        expect(entry.api_name).to be_present
        expect(entry.display_name).to be_present
        expect(entry.default_output_vector_size).to be_a(Integer)
        expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.status)
      end

      it "has pricing unless retired" do
        next if entry.retired?

        # Float, not Integer: RegistryData and the generator divide this by 1_000_000, and
        # an Integer would silently floor the result to 0.
        expect(entry.input_per_million).to be_a(Float)
      end
    end
  end
end
