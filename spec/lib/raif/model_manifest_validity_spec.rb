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

  # These guard against the whole file going vacuously green: every describe block below is
  # built by iterating these three collections at load time, so an empty manifest directory (or
  # a loader regression that returns no entries) would otherwise produce zero per-entry examples
  # and this spec would still report success.
  it "loaded a nonempty set of llm entries" do
    expect(entries).not_to be_empty
  end

  it "loaded a nonempty set of embedding entries" do
    expect(manifest.embedding_entries).not_to be_empty
  end

  it "loaded a nonempty set of provider files" do
    expect(manifest.provider_files).not_to be_empty
  end

  manifest.provider_files.each_key do |provider_name|
    describe "#{provider_name} references" do
      it "declares HTTPS URLs" do
        refs = manifest.references_for(provider_name)
        expect(refs).not_to be_empty

        refs.each_value do |url|
          expect(url).to start_with("https://")
        end
      end
    end
  end

  entries.each do |entry|
    describe entry.key.to_s do
      it "prefixes the key with its provider" do
        prefix = if entry.provider_name == :open_ai
          Raif::ModelManifest::OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch(entry.endpoint)
        else
          "#{entry.provider_name}_"
        end
        expect(entry.key.to_s).to start_with(prefix)
      end

      it "has required fields" do
        expect(entry.api_name).to be_present
        expect(entry.display_name).to be_present
      end

      it "has exactly the known capability keys, each a known boolean or tool list, and a recognized lifecycle status" do
        expect(entry.capabilities.keys.sort).to eq(Raif::ModelManifest::CAPABILITY_KEYS.sort)
        entry.capabilities.except(:provider_managed_tools).each_value do |value|
          expect(value).to be(true).or be(false)
        end
        expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.lifecycle.fetch(:status))
      end

      it "declares only known provider-managed tools, as symbols" do
        tools = entry.capabilities.fetch(:provider_managed_tools)
        tools.each { |tool| expect(tool).to be_a(Symbol) }

        unknown = tools.map(&:to_s) - Raif::ModelManifest::PROVIDER_MANAGED_TOOL_CLASSES.keys
        expect(unknown).to be_empty
      end

      it "has positive numeric pricing unless retired" do
        next if entry.retired?

        expect(entry.pricing.fetch(:input_per_million)).to be_a(Numeric)
        expect(entry.pricing.fetch(:input_per_million)).to be > 0
        expect(entry.pricing.fetch(:output_per_million)).to be_a(Numeric)
        expect(entry.pricing.fetch(:output_per_million)).to be > 0
      end

      it "has Date objects for whichever lifecycle dates it declares" do
        %i[added_on deprecated_on retirement_date].each do |field|
          value = entry.lifecycle.fetch(field)
          expect(value).to be_a(Date) if value
        end
      end

      it "has coherent lifecycle fields" do
        if entry.deprecated?
          expect(entry.lifecycle.fetch(:retirement_date)).to be_present
        end

        replacement = entry.lifecycle.fetch(:replacement_key)
        if replacement
          target = entries.find { |e| e.key == replacement }
          expect(target).to be_present, "replacement_key #{replacement} not found in manifest"
          expect(target).to be_active, "replacement for a deprecated model must be active" if entry.deprecated?
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
        expect(Raif::ModelManifest::LIFECYCLE_STATUSES).to include(entry.lifecycle.fetch(:status))
      end

      it "has positive numeric pricing unless retired" do
        next if entry.retired?

        expect(entry.input_per_million).to be_a(Numeric)
        expect(entry.input_per_million).to be > 0
      end

      it "has Date objects for whichever lifecycle dates it declares" do
        %i[added_on deprecated_on retirement_date].each do |field|
          value = entry.lifecycle.fetch(field)
          expect(value).to be_a(Date) if value
        end
      end
    end
  end
end
