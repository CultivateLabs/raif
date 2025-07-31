---
layout: default
title: Images/Files/PDF's
nav_order: 5
description: "Working with images, files, and PDFs in Raif"
---

# Images/Files/PDF's

## Sending Images/Files/PDF's to the LLM

Raif supports images, files, and PDF's in the messages sent to the LLM.

To include an image, file/PDF in a message, you can use the `Raif::ModelImageInput` and `Raif::ModelFileInput`.

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

### Images/Files/PDF's in Tasks

You can include images and files/PDF's when running a `Raif::Task`:

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