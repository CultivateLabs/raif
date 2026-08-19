# frozen_string_literal: true

# Regenerates all artifacts derived from model_manifest/*.yml.
# See bin/generate_llm_registry.
require "raif/model_manifest"
require "raif/model_manifest/registry_data"
require "raif/model_manifest/generator"

manifest = Raif::ModelManifest.load
Raif::ModelManifest::Generator.write_all!(manifest, root: Raif::Engine.root)
puts "Regenerated: lib/raif/default_llms.rb, lib/raif/default_embedding_models.rb, config/locales/en.yml (model names), " \
  "initializer template, docs/_getting_started/setup.md"
