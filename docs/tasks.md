---
layout: default
title: Tasks
nav_order: 3
---

# Tasks
{: .no_toc }

Single-shot AI operations with defined prompts and response formats.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Tasks represent single AI operations that take input, process it through an LLM, and return structured responses. Perfect for:

- Content generation and summarization
- Data extraction and classification
- Translation and text processing

---

## Creating a Task

```bash
rails generate raif:task ContentSummarizer --response-format html
```

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

---

## Response Formats

### Text Format
```ruby
llm_response_format :text  # Plain text responses
```

### HTML Format  
```ruby
llm_response_format :html  # HTML-formatted responses
```

### JSON Format
```ruby
llm_response_format :json

json_response_schema do
  string :name, description: "The person's name"
  string :email, description: "The person's email address"
  string :phone, description: "The person's phone number", required: false
end
```

---

## Usage

### Basic Usage

```ruby
task = Raif::Tasks::ContentSummarizer.run(
  content: "Long content here...",
  max_length: 200,
  creator: current_user
)

# Access results
puts task.raw_response      # Raw LLM response
puts task.parsed_response   # Parsed response (JSON parsed if format is :json)
puts task.status           # :completed, :failed, :in_progress, or :pending
```

### In Controllers

```ruby
class DocumentsController < ApplicationController
  def summarize
    task = Raif::Tasks::ContentSummarizer.run(
      content: params[:content],
      max_length: params[:max_length],
      creator: current_user
    )
    
    if task.completed?
      render json: { summary: task.parsed_response }
    else
      render json: { error: "Summarization failed" }, status: :unprocessable_entity
    end
  end
end
```

### With Model Tools

```ruby
task = Raif::Tasks::ResearchTask.run(
  topic: "renewable energy",
  creator: current_user,
  available_model_tools: [
    "Raif::ModelTools::ProviderManaged::WebSearch",
    "Raif::ModelTools::WikipediaSearch"
  ]
)
```

---

## Configuration

### Temperature Control
```ruby
llm_temperature 0.1  # More focused
llm_temperature 0.9  # More creative
```

### Language Preference
```ruby
task = Raif::Tasks::ContentSummarizer.run(
  content: "Content to summarize",
  creator: current_user,
  requested_language_key: "es"  # Spanish
)
```

### File Processing
```ruby
# Include files/images
pdf_file = Raif::ModelFileInput.new(input: "path/to/document.pdf")
image = Raif::ModelImageInput.new(input: "path/to/chart.png")

task = Raif::Tasks::DocumentAnalysis.run(
  creator: current_user,
  files: [pdf_file],
  images: [image]
)
```

---

## Error Handling

```ruby
task = Raif::Tasks::ContentSummarizer.run(
  content: "Some content",
  creator: current_user
)

case task.status
when :completed
  result = task.parsed_response
when :failed
  Rails.logger.error "Task failed for user #{current_user.id}"
end

# Or simple check
if task.completed?
  # Process the result
  result = task.parsed_response
end
```

---

## Testing

```ruby
RSpec.describe Raif::Tasks::ContentSummarizer do
  let(:user) { create(:user) }
  
  it "summarizes content" do
    stub_raif_task(described_class) do |messages, model_completion|
      "This is a concise summary of the provided content."
    end
    
    task = described_class.run(
      content: "Long content here...",
      max_length: 50,
      creator: user
    )
    
    expect(task).to be_completed
    expect(task.parsed_response).to eq("This is a concise summary of the provided content.")
  end
  
  it "includes content in the prompt" do
    stub_raif_task(described_class) do |messages, model_completion|
      prompt = messages.first["content"]
      expect(prompt).to include("Long content here...")
      "Summary"
    end
    
    described_class.run(content: "Long content here...", creator: user)
  end
end
```

---

## Advanced Patterns

### Task Inheritance

```ruby
class Raif::Tasks::BaseAnalysisTask < Raif::ApplicationTask
  llm_temperature 0.3
  
  def build_system_prompt
    "You are an expert analyst. Be thorough and accurate."
  end
end

class Raif::Tasks::FinancialAnalysis < Raif::Tasks::BaseAnalysisTask
  attr_accessor :financial_data
  
  def build_prompt
    "Analyze the following financial data: #{financial_data}"
  end
end
```

### Re-running Failed Tasks

```ruby
if task.failed?
  task.re_run
end
``` 