---
layout: default
title: Tasks
nav_order: 3
---

# Tasks
{: .no_toc }

Tasks are single-shot AI operations with defined prompts and response formats. They're perfect for one-time AI operations like content generation, data analysis, or text processing.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

A Task in Raif represents a single AI operation that takes input, processes it through an LLM, and returns a structured response. Tasks are ideal for:

- Content generation
- Text summarization
- Data extraction
- Classification tasks
- Translation

## Creating a Task

Use the generator to create a new task:

```bash
rails generate raif:task ContentSummarizer --response-format html
```

This creates a task class at `app/models/raif/tasks/content_summarizer.rb`:

```ruby
class Raif::Tasks::ContentSummarizer < Raif::ApplicationTask
  llm_response_format :html
  llm_temperature 0.7
  
  attr_accessor :content, :max_length
  
  def build_system_prompt
    "You are a helpful assistant that summarizes content clearly and concisely."
  end
  
  def build_prompt
    "Please summarize the following content in #{max_length || 100} words or less:\n\n#{content}"
  end
end
```

## Response Formats

Tasks support three response formats:

### Text Format
```ruby
llm_response_format :text
```
Returns plain text responses.

### HTML Format  
```ruby
llm_response_format :html
```
Returns HTML-formatted responses, useful for rich content.

### JSON Format
```ruby
llm_response_format :json
```
Returns structured JSON data. You can define a schema:

```ruby
class Raif::Tasks::DataExtractor < Raif::ApplicationTask
  llm_response_format :json
  
  def build_json_schema
    {
      type: "object",
      properties: {
        name: { type: "string" },
        email: { type: "string" },
        phone: { type: "string" }
      },
      required: ["name"]
    }
  end
end
```

## Using Tasks

### In Controllers

```ruby
class DocumentsController < ApplicationController
  def summarize
    task = Raif::Tasks::ContentSummarizer.new
    task.content = params[:content]
    task.max_length = params[:max_length]
    
    result = task.run!
    
    render json: { summary: result.response_text }
  end
end
```

### In Background Jobs

```ruby
class SummarizeDocumentJob < ApplicationJob
  def perform(document_id)
    document = Document.find(document_id)
    
    task = Raif::Tasks::ContentSummarizer.new
    task.content = document.content
    task.max_length = 200
    
    result = task.run!
    
    document.update!(summary: result.response_text)
  end
end
```

## Configuration Options

### Temperature
Control randomness in responses:

```ruby
llm_temperature 0.1  # More focused
llm_temperature 0.9  # More creative
```

### Model Selection
Specify which LLM to use:

```ruby
llm_model :gpt_4o_mini
# or
llm_model :claude_3_5_sonnet
```

### Custom Validation

Add validation to your task inputs:

```ruby
class Raif::Tasks::ContentSummarizer < Raif::ApplicationTask
  validates :content, presence: true, length: { minimum: 10 }
  validates :max_length, numericality: { greater_than: 0 }
end
```

## Error Handling

Tasks include built-in error handling:

```ruby
task = Raif::Tasks::ContentSummarizer.new
task.content = "Some content"

begin
  result = task.run!
  puts result.response_text
rescue Raif::TaskValidationError => e
  puts "Validation failed: #{e.message}"
rescue Raif::LlmError => e
  puts "LLM error: #{e.message}"
end
```

## Testing Tasks

Raif provides test helpers for tasks:

```ruby
RSpec.describe Raif::Tasks::ContentSummarizer do
  it "summarizes content" do
    task = described_class.new
    task.content = "Long content here..."
    task.max_length = 50
    
    stub_raif_task(task, response: "Short summary")
    
    result = task.run!
    expect(result.response_text).to eq("Short summary")
  end
end
``` 