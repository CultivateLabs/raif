# frozen_string_literal: true

# One-time bootstrap: converts the hand-written Raif.default_llms registry,
# the embedding registry, and config/locales/en.yml model names into
# model_manifest/*.yml. Deleted once the manifest becomes the source of truth.
require "raif/model_manifest"
require "fileutils"

ADAPTER_TO_PROVIDER = {
  "Raif::Llms::Anthropic" => "anthropic",
  "Raif::Llms::Bedrock" => "bedrock",
  "Raif::Llms::OpenRouter" => "open_router",
  "Raif::Llms::XAi" => "x_ai",
  "Raif::Llms::Google" => "google"
}.freeze

EMBEDDING_ADAPTER_TO_PROVIDER = {
  "Raif::EmbeddingModels::OpenAi" => "open_ai",
  "Raif::EmbeddingModels::Bedrock" => "bedrock",
  "Raif::EmbeddingModels::Google" => "google"
}.freeze

REFERENCES = {
  "open_ai" => {
    "models_doc" => "https://platform.openai.com/docs/models",
    "pricing" => "https://platform.openai.com/docs/pricing",
    "deprecations" => "https://platform.openai.com/docs/deprecations"
  },
  "anthropic" => {
    "models_doc" => "https://docs.claude.com/en/docs/about-claude/models",
    "pricing" => "https://claude.com/pricing",
    "deprecations" => "https://docs.claude.com/en/docs/about-claude/model-deprecations"
  },
  "bedrock" => {
    "models_doc" => "https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html",
    "pricing" => "https://aws.amazon.com/bedrock/pricing/",
    "deprecations" => "https://docs.aws.amazon.com/bedrock/latest/userguide/model-lifecycle.html"
  },
  "open_router" => {
    "models_doc" => "https://openrouter.ai/models",
    "pricing" => "https://openrouter.ai/models",
    "deprecations" => "https://openrouter.ai/docs/models"
  },
  "x_ai" => {
    "models_doc" => "https://docs.x.ai/docs/models",
    "pricing" => "https://docs.x.ai/docs/models",
    "deprecations" => "https://docs.x.ai/docs/models"
  },
  "google" => {
    "models_doc" => "https://ai.google.dev/gemini-api/docs/models",
    "pricing" => "https://ai.google.dev/gemini-api/docs/pricing",
    "deprecations" => "https://ai.google.dev/gemini-api/docs/deprecations"
  }
}.freeze

REVERSE_PROVIDER_MANAGED_TOOL_CLASSES = Raif::ModelManifest::PROVIDER_MANAGED_TOOL_CLASSES.invert.freeze

MODEL_NAMES = I18n.t("raif.model_names")
EMBEDDING_MODEL_NAMES = I18n.t("raif.embedding_model_names")

# Undoes float noise introduced by the Bedrock "/ 1000" divisors in
# lib/raif/llm_registry.rb (e.g. 0.010 / 1000 * 1_000_000 => 9.999999999999999).
def per_million(cost)
  ("%.10g" % (cost * 1_000_000)).to_f
end

def provider_managed_tools_for(config)
  Array(config[:supported_provider_managed_tools]).map do |klass|
    REVERSE_PROVIDER_MANAGED_TOOL_CLASSES.fetch(klass.name)
  end
end

# images/pdfs are not modeled in the current registry, so they're seeded
# here from researched values, keyed by key prefix.
def images_pdfs_for(key)
  key_s = key.to_s

  if key_s.start_with?("anthropic_")
    [true, true]
  elsif key_s.start_with?("bedrock_claude_")
    [true, true]
  elsif key_s.start_with?("bedrock_amazon_nova_")
    [true, false]
  elsif key_s.start_with?("bedrock_deepseek_") || key_s.start_with?("bedrock_gpt_oss_")
    [false, false]
  elsif key_s.start_with?("open_router_claude_") || key_s.start_with?("open_router_gemini_")
    [true, true]
  elsif key_s.start_with?("open_router_")
    [false, false]
  elsif key_s.start_with?("x_ai_")
    [true, false]
  elsif key_s.start_with?("google_")
    [true, true]
  else
    raise "No images/pdfs seeding rule for key: #{key_s}"
  end
end

def capabilities_for(config, adapter_class_name:, images:, pdfs:)
  settings = config[:model_provider_settings] || {}
  adapter_defaults = Raif::ModelManifest::ADAPTER_DEFAULTS.fetch(adapter_class_name)

  structured_outputs = if settings.key?(:supports_structured_outputs)
    settings[:supports_structured_outputs]
  else
    adapter_defaults.fetch("structured_outputs")
  end
  batch_inference = settings.key?(:supports_batch_inference) ? settings[:supports_batch_inference] : adapter_defaults.fetch("batch_inference")

  {
    "temperature" => !(settings[:supports_temperature] == false),
    "structured_outputs" => structured_outputs,
    "native_tool_use" => config.fetch(:supports_native_tool_use, true),
    "streaming" => !config.fetch(:key).to_s.match?(/\Abedrock_gpt_oss_/),
    "batch_inference" => batch_inference,
    "images" => images,
    "pdfs" => pdfs,
    "provider_managed_tools" => provider_managed_tools_for(config)
  }
end

def lifecycle_node
  {
    "status" => "active",
    "added_on" => nil,
    "deprecated_on" => nil,
    "retirement_date" => nil,
    "replacement_key" => nil,
    "migration_note" => nil
  }
end

def pricing_node(config)
  {
    "input_per_million" => per_million(config.fetch(:input_token_cost)),
    "output_per_million" => per_million(config.fetch(:output_token_cost))
  }
end

def build_model_node(config, adapter_class_name:)
  key = config.fetch(:key)
  images, pdfs = images_pdfs_for(key)

  node = {
    "key" => key.to_s,
    "api_name" => config.fetch(:api_name),
    "display_name" => MODEL_NAMES.fetch(key)
  }
  node["max_completion_tokens"] = config[:max_completion_tokens] if config.key?(:max_completion_tokens)
  node["pricing"] = pricing_node(config)
  node["capabilities"] = capabilities_for(config, adapter_class_name: adapter_class_name, images: images, pdfs: pdfs)
  node["lifecycle"] = lifecycle_node
  node["verification"] = nil
  node
end

FileUtils.mkdir_p(Raif::ModelManifest::MANIFEST_DIR)

default_llms = Raif.default_llms

ADAPTER_TO_PROVIDER.each do |adapter_class_name, provider|
  configs = default_llms.fetch(adapter_class_name.constantize)
  models = configs.map { |config| build_model_node(config, adapter_class_name: adapter_class_name) }

  data = {
    "provider" => provider,
    "references" => REFERENCES.fetch(provider),
    "models" => models
  }

  File.write(File.join(Raif::ModelManifest::MANIFEST_DIR, "#{provider}.yml"), data.to_yaml)
end

# OpenAI: pair up completions + responses configs by key_base. The registry
# builds responses configs by deriving from completions configs (see
# lib/raif/llm_registry.rb), so api_name/pricing/lifecycle are identical
# between endpoints wherever both exist; only capabilities differ per endpoint.
completions_prefix = Raif::ModelManifest::OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch("completions")
responses_prefix = Raif::ModelManifest::OPEN_AI_ENDPOINT_KEY_PREFIXES.fetch("responses")

grouped = {}

default_llms.fetch(Raif::Llms::OpenAiCompletions).each do |config|
  key_base = config.fetch(:key).to_s.sub(/\A#{Regexp.escape(completions_prefix)}/, "")
  grouped[key_base] ||= {}
  grouped[key_base]["completions"] = config
end

default_llms.fetch(Raif::Llms::OpenAiResponses).each do |config|
  key_base = config.fetch(:key).to_s.sub(/\A#{Regexp.escape(responses_prefix)}/, "")
  grouped[key_base] ||= {}
  grouped[key_base]["responses"] = config
end

open_ai_models = grouped.map do |key_base, endpoints|
  completions_config = endpoints["completions"]
  responses_config = endpoints["responses"]
  # Prefer the completions display name (e.g. "OpenAI GPT-5") for models that
  # have both; responses-only models (the *_pro keys) have no other name.
  # Always strip " (Responses API)": the downstream generator re-appends it
  # per responses endpoint, so this must stay endpoint-agnostic.
  primary_config = completions_config || responses_config
  display_key = completions_config ? completions_config.fetch(:key) : responses_config.fetch(:key)
  display_name = MODEL_NAMES.fetch(display_key).sub(/ \(Responses API\)\z/, "")

  node = {
    "key_base" => key_base,
    "api_name" => primary_config.fetch(:api_name),
    "display_name" => display_name,
    "pricing" => pricing_node(primary_config),
    "lifecycle" => lifecycle_node,
    "endpoints" => {}
  }

  if completions_config
    node["endpoints"]["completions"] = {
      "capabilities" => capabilities_for(completions_config, adapter_class_name: "Raif::Llms::OpenAiCompletions", images: true, pdfs: false),
      "verification" => nil
    }
  end

  if responses_config
    node["endpoints"]["responses"] = {
      "capabilities" => capabilities_for(responses_config, adapter_class_name: "Raif::Llms::OpenAiResponses", images: true, pdfs: true),
      "verification" => nil
    }
  end

  node
end

open_ai_data = {
  "provider" => "open_ai",
  "references" => REFERENCES.fetch("open_ai"),
  "models" => open_ai_models
}

File.write(File.join(Raif::ModelManifest::MANIFEST_DIR, "open_ai.yml"), open_ai_data.to_yaml)

default_embedding_models = Raif.default_embedding_models

embedding_providers = EMBEDDING_ADAPTER_TO_PROVIDER.map do |adapter_class_name, provider|
  configs = default_embedding_models.fetch(adapter_class_name.constantize)

  models = configs.map do |config|
    key = config.fetch(:key)
    {
      "key" => key.to_s,
      "api_name" => config.fetch(:api_name),
      "display_name" => EMBEDDING_MODEL_NAMES.fetch(key),
      "input_per_million" => per_million(config.fetch(:input_token_cost)),
      "default_output_vector_size" => config.fetch(:default_output_vector_size),
      "lifecycle" => lifecycle_node,
      "verification" => nil
    }
  end

  {
    "provider" => provider,
    "adapter" => adapter_class_name,
    "models" => models
  }
end

embeddings_data = { "providers" => embedding_providers }

File.write(File.join(Raif::ModelManifest::MANIFEST_DIR, "embeddings.yml"), embeddings_data.to_yaml)

puts "Wrote #{ADAPTER_TO_PROVIDER.size + 1} LLM provider manifest files and embeddings.yml to #{Raif::ModelManifest::MANIFEST_DIR}"
