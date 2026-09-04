# frozen_string_literal: true

require "raif/model_manifest"
require "raif/model_manifest/registry_data"

# The runtime registry, built from lib/raif/model_manifest/definitions/*.rb.
# lib/raif/engine.rb iterates default_llms and default_embedding_models in
# after_initialize and registers each config; Raif::Configuration reads
# default_streaming_unsupported_model_keys for the streaming fallback default.
# Everything is memoized: the definitions are evaluated once per process.
module Raif
  def self.model_manifest
    @model_manifest ||= Raif::ModelManifest.load
  end

  def self.default_llms
    @default_llms ||= Raif::ModelManifest::RegistryData.llm_configs(model_manifest).transform_keys(&:constantize)
  end

  def self.default_embedding_models
    @default_embedding_models ||= Raif::ModelManifest::RegistryData.embedding_configs(model_manifest).transform_keys(&:constantize)
  end

  # Read while Raif::Configuration initializes, which can happen inside a host
  # app's initializer before autoloading is ready, so this must not
  # constantize anything.
  def self.default_streaming_unsupported_model_keys
    @default_streaming_unsupported_model_keys ||= Raif::ModelManifest::RegistryData.streaming_unsupported_keys(model_manifest).freeze
  end
end
