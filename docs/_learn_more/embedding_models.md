---
layout: default
title: Embedding Models
nav_order: 6
description: "Working with vector embeddings in Raif"
---

# Embedding Models

Raif supports generation of vector embeddings. You can enable and configure embedding models in your Raif initializer:

```ruby
Raif.configure do |config|
  config.open_ai_embedding_models_enabled = true
  config.bedrock_embedding_models_enabled = true
  config.google_embedding_models_enabled = true

  config.default_embedding_model_key = "open_ai_text_embedding_3_small"
end
```

Google embeddings use the same API key as Google LLM models. Configure `config.google_api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]` if you are not already doing so in your initializer.

## Supported Embedding Models

Raif currently supports the following embedding models:

### OpenAI
- `open_ai_text_embedding_3_small`
- `open_ai_text_embedding_3_large`
- `open_ai_text_embedding_ada_002`

### AWS Bedrock
- `bedrock_titan_embed_text_v2`

### Google AI
- `google_gemini_embedding_2`

## Creating Embeddings

By default, Raif will use `Raif.config.default_embedding_model_key` as the model for creating embeddings. To create an embedding for a piece of text:

```ruby
# Generate an embedding for a piece of text
embedding = Raif.generate_embedding!("Your text here")

# Generate an embedding for a piece of text with a specific number of dimensions
embedding = Raif.generate_embedding!("Your text here", dimensions: 1024)

# If you're using an OpenAI embedding model, you can pass an array of strings to embed multiple texts at once
embeddings = Raif.generate_embedding!([
  "Your text here",
  "Your other text here"
])
```

Or to generate embeddings for a piece of text with a specific model:

```ruby
model = Raif.embedding_model(:open_ai_text_embedding_3_small)
embedding = model.generate_embedding!("Your text here")
```

## Smoke Testing Embedding Models

Use `bin/smoke_embedding_models` to verify credentials and connectivity for the embedding models you have enabled. The script skips providers that do not have credentials configured.

```bash
bin/smoke_embedding_models --list
bin/smoke_embedding_models google
bin/smoke_embedding_models google_gemini_embedding_2
bin/smoke_embedding_models ALL
```

---

**Read next:** [Customization](customization)
