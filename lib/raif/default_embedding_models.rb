# frozen_string_literal: true

# GENERATED FILE - DO NOT EDIT.
# Source of truth: model_manifest/*.rb
# Regenerate with: bin/generate_llm_registry

module Raif
  def self.default_embedding_models
    {
      Raif::EmbeddingModels::OpenAi => [
        {
          key: :open_ai_text_embedding_3_large,
          api_name: "text-embedding-3-large",
          input_token_cost: 0.13 / 1_000_000,
          default_output_vector_size: 3072
        },
        {
          key: :open_ai_text_embedding_3_small,
          api_name: "text-embedding-3-small",
          input_token_cost: 0.02 / 1_000_000,
          default_output_vector_size: 1536
        },
        {
          key: :open_ai_text_embedding_ada_002,
          api_name: "text-embedding-ada-002",
          input_token_cost: 0.01 / 1_000_000,
          default_output_vector_size: 1536
        }
      ],
      Raif::EmbeddingModels::Bedrock => [
        {
          key: :bedrock_titan_embed_text_v2,
          api_name: "amazon.titan-embed-text-v2:0",
          input_token_cost: 0.01 / 1_000_000,
          default_output_vector_size: 1024
        }
      ],
      Raif::EmbeddingModels::Google => [
        {
          key: :google_gemini_embedding_2,
          api_name: "gemini-embedding-2-preview",
          input_token_cost: 0.2 / 1_000_000,
          default_output_vector_size: 3072
        }
      ]
    }
  end
end
