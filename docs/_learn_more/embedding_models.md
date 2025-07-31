---
layout: default
title: Embedding Models
nav_order: 5
description: "Working with vector embeddings in Raif"
---

# Embedding Models

Raif supports generation of vector embeddings. You can enable and configure embedding models in your Raif configuration:

```ruby
Raif.configure do |config|
  config.open_ai_embedding_models_enabled = true
  config.bedrock_embedding_models_enabled = true
  
  config.default_embedding_model_key = "open_ai_text_embedding_3_small"
end
```

## Supported Embedding Models

Raif currently supports the following embedding models:

### OpenAI
- `open_ai_text_embedding_3_small`
- `open_ai_text_embed ding_3_large`
- `open_ai_text_embedding_ada_002`

### AWS Bedrock
- `bedrock_titan_embed_text_v2`

## Creating Embeddings

By default, Raif will used `Raif.config.default_embedding_model_key` to create embeddings. To create an embedding for a piece of text:

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