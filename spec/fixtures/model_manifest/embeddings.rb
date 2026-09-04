# frozen_string_literal: true

embeddings do |e|
  e.provider :open_ai, adapter: "Raif::EmbeddingModels::OpenAi" do |p|
    p.model(
      key: :open_ai_test_embedding,
      api_name: "text-embedding-test",
      display_name: "OpenAI Test Embedding",
      input_per_million: 0.02,
      default_output_vector_size: 1536,
      lifecycle: {
        status: :active,
        added_on: Date.new(2024, 1, 25)
      }
    )

    p.model(
      key: :open_ai_test_embedding_gone,
      api_name: "text-embedding-test-gone",
      display_name: "OpenAI Test Embedding Gone",
      input_per_million: 0.02,
      default_output_vector_size: 1536,
      lifecycle: {
        status: :retired,
        added_on: Date.new(2022, 1, 1),
        deprecated_on: Date.new(2023, 1, 1),
        retirement_date: Date.new(2023, 6, 1),
        replacement_key: :open_ai_test_embedding
      }
    )
  end
end
