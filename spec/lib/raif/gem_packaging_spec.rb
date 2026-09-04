# frozen_string_literal: true

require "rails_helper"
require "raif/model_manifest"

RSpec.describe "gem packaging" do
  let(:gemspec) { Gem::Specification.load(Raif::Engine.root.join("raif.gemspec").to_s) }

  it "ships every model manifest definition file" do
    definitions = Dir[Raif::Engine.root.join("lib/raif/model_manifest/definitions/*.rb").to_s]
    expect(definitions.size).to eq(7)

    relative = definitions.map { |path| path.delete_prefix("#{Raif::Engine.root}/") }
    expect(gemspec.files).to include(*relative)
  end

  it "loads the runtime manifest from the shipped definitions directory" do
    expect(Raif::ModelManifest::MANIFEST_DIR).to eq(Raif::Engine.root.join("lib/raif/model_manifest/definitions").to_s)
    expect(Raif::ModelManifest.load.llm_entries).to_not be_empty
  end
end
