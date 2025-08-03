---
layout: default
title: Images/Files/PDFs
nav_order: 4
description: "Support for including images and PDF in prompts"
---

{% include table-of-contents.md %}

# Sending Images/Files/PDFs to the LLM

Raif supports including images, files, and PDF's in the messages sent to the LLM. This page describes using them as inputs to the LLM. If you're looking to create images as outputs, see the [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) documentation.

To include an image or file/PDF in a message, you can use the `Raif::ModelImageInput` and `Raif::ModelFileInput`.

To include an image:
```ruby
# From a local file
image = Raif::ModelImageInput.new(input: "path/to/image.png")

# From a URL
image = Raif::ModelImageInput.new(url: "https://example.com/image.png")

# From an ActiveStorage attachment (assumes you have a User model with an avatar attachment)
image = Raif::ModelImageInput.new(input: user.avatar)

# Then chat with the LLM
llm = Raif.llm(:open_ai_gpt_4o)
model_completion = llm.chat(messages: [
  { role: "user", content: ["What's in this image?", image]}
])
```

To include a file/PDF:
```ruby
# From a local file
file = Raif::ModelFileInput.new(input: "path/to/file.pdf")

# From a URL
file = Raif::ModelFileInput.new(url: "https://example.com/file.pdf")

# From an ActiveStorage attachment (assumes you have a Document model with a pdf attachment)
file = Raif::ModelFileInput.new(input: document.pdf)

# Then chat with the LLM
llm = Raif.llm(:open_ai_gpt_4o)
model_completion = llm.chat(messages: [
  { role: "user", content: ["What's in this file?", file]}
])
```

# Images/Files/PDFs in Tasks

You can include images and files/PDFs when running a `Raif::Task`:

To include a file/PDF:
```ruby
file = Raif::ModelFileInput.new(input: "path/to/file.pdf")

# Assumes you've created a PdfContentExtraction task
task = Raif::Tasks::PdfContentExtraction.run(
  creator: current_user,
  files: [file]
)
```

To include an image:
```ruby
image = Raif::ModelImageInput.new(input: "path/to/image.png")

# Assumes you've created a ImageDescriptionGeneration task
task = Raif::Tasks::ImageDescriptionGeneration.run(
  creator: current_user,
  images: [image]
)
```

---

**Read next:** [JSON Schemas](json_schemas)