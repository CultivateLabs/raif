# frozen_string_literal: true

module Raif
  class << self
    attr_accessor :embedding_model_registry
  end

  def self.generate_embedding!(input, dimensions: nil)
    embedding_model = embedding_model(default_embedding_model_key.to_sym)
    embedding_model.generate_embedding!(input, dimensions:)
  end

  def self.default_embedding_model_key
    Rails.env.test? ? :raif_test_embedding_model : Raif.config.default_embedding_model_key
  end

  def self.register_embedding_model(embedding_model_class, embedding_model_config)
    embedding_model = embedding_model_class.new(**embedding_model_config)

    unless embedding_model.valid?
      raise ArgumentError, "The embedding model you tried to register is invalid: #{embedding_model.errors.full_messages.join(", ")}"
    end

    @embedding_model_registry ||= {}
    @embedding_model_registry[embedding_model.key] = embedding_model_config.merge(embedding_model_class: embedding_model_class)
  end

  def self.embedding_model(model_key)
    embedding_model_config = embedding_model_registry[model_key]

    if embedding_model_config.nil?
      raise ArgumentError, "No embedding model found for model key: #{model_key}. Available models: #{available_embedding_model_keys.join(", ")}"
    end

    embedding_model_class = embedding_model_config[:embedding_model_class]
    embedding_model_class.new(**embedding_model_config.except(:embedding_model_class))
  end

  def self.available_embedding_models
    embedding_model_registry.values
  end

  def self.available_embedding_model_keys
    embedding_model_registry.keys
  end

  def self.embedding_model_config(model_key)
    embedding_model_registry[model_key]
  end

  def self.default_embedding_models
    {
      Raif::EmbeddingModels::OpenAi => [
        {
          key: :open_ai_text_embedding_3_large,
          api_name: "text-embedding-3-large",
          input_token_cost: 0.13 / 1_000_000,
          default_output_vector_size: 3072,
        },
        {
          key: :open_ai_text_embedding_3_small,
          api_name: "text-embedding-3-small",
          input_token_cost: 0.02 / 1_000_000,
          default_output_vector_size: 1536,
        },
        {
          key: :open_ai_text_embedding_ada_002,
          api_name: "text-embedding-ada-002",
          input_token_cost: 0.01 / 1_000_000,
          default_output_vector_size: 1536,
        },
      ],
      Raif::EmbeddingModels::Bedrock => [
        {
          key: :bedrock_titan_embed_text_v2,
          api_name: "amazon.titan-embed-text-v2:0",
          input_token_cost: 0.01 / 1_000_000,
          default_output_vector_size: 1024,
        },
      ]
    }
  end
end
