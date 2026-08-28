# frozen_string_literal: true

embeddings do |e|
  e.provider :open_ai, adapter: "Raif::EmbeddingModels::OpenAi" do |p|
    p.model(
      key: :open_ai_text_embedding_3_large,
      api_name: "text-embedding-3-large",
      display_name: "OpenAI Text Embedding 3 Large",
      input_per_million: 0.13,
      default_output_vector_size: 3072,
      lifecycle: {
        status: :active
      }
    )

    p.model(
      key: :open_ai_text_embedding_3_small,
      api_name: "text-embedding-3-small",
      display_name: "OpenAI Text Embedding 3 Small",
      input_per_million: 0.02,
      default_output_vector_size: 1536,
      lifecycle: {
        status: :active
      }
    )

    p.model(
      key: :open_ai_text_embedding_ada_002,
      api_name: "text-embedding-ada-002",
      display_name: "OpenAI Text Embedding Ada 002",
      input_per_million: 0.01,
      default_output_vector_size: 1536,
      lifecycle: {
        status: :active
      }
    )
  end

  e.provider :bedrock, adapter: "Raif::EmbeddingModels::Bedrock" do |p|
    p.model(
      key: :bedrock_titan_embed_text_v2,
      api_name: "amazon.titan-embed-text-v2:0",
      display_name: "AWS Bedrock Titan Text Embeddings v2",
      input_per_million: 0.01,
      default_output_vector_size: 1024,
      lifecycle: {
        status: :active
      }
    )
  end

  e.provider :google, adapter: "Raif::EmbeddingModels::Google" do |p|
    p.model(
      key: :google_gemini_embedding_2,
      api_name: "gemini-embedding-2-preview",
      display_name: "Google Gemini Embedding 2",
      input_per_million: 0.2,
      default_output_vector_size: 3072,
      lifecycle: {
        status: :active
      }
    )
  end
end
