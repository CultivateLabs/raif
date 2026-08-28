# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::EmbeddingModel, type: :model do
  it "generates test embeddings" do
    model = Raif.embedding_model(:raif_test_embedding_model)
    embedding = model.generate_embedding!("Hello, world!")
    expect(embedding).to be_a(Array)
    expect(embedding.size).to eq(1536)
  end

  it "defaults to raif_test_embedding_model in test environment" do
    expect(Raif.default_embedding_model_key).to eq(:raif_test_embedding_model)
  end

  it "names every built in embedding model from its manifest display_name" do
    Raif.default_embedding_models.values.flatten.each do |embedding_model_config|
      embedding_model = Raif.embedding_model(embedding_model_config[:key])
      expect(embedding_model.name).to eq(embedding_model_config[:display_name])
    end
  end

  describe "#name" do
    context "when a host app provides an I18n translation" do
      it "prefers the translation over display_name" do
        embedding_model = Raif::EmbeddingModel.new(
          key: :open_ai_text_embedding_3_large,
          api_name: "text-embedding-3-large",
          display_name: "Custom Display Name",
          default_output_vector_size: 3072
        )

        I18n.backend.store_translations(:en, raif: { embedding_model_names: { open_ai_text_embedding_3_large: "Host App Name" } })
        expect(embedding_model.name).to eq("Host App Name")
      ensure
        I18n.backend.reload!
      end
    end

    context "when I18n translation does not exist" do
      it "falls back to display_name when provided" do
        embedding_model = Raif::EmbeddingModel.new(
          key: :custom_embedding_key,
          api_name: "custom-embedding",
          display_name: "My Custom Embedding Model",
          default_output_vector_size: 1536
        )

        expect(embedding_model.name).to eq("My Custom Embedding Model")
      end

      it "falls back to humanized key when display_name is not provided" do
        embedding_model = Raif::EmbeddingModel.new(
          key: :my_custom_embedding,
          api_name: "custom-embedding",
          default_output_vector_size: 1536
        )

        expect(embedding_model.name).to eq("My custom embedding")
      end
    end
  end
end
