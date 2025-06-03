---
layout: default
title: Images, Files & PDFs
nav_order: 7
description: "Working with images, files, and PDFs in Raif"
---

# Images, Files & PDFs
{: .no_toc }

Raif supports sending images, files, and PDF documents to LLMs for analysis, processing, and content extraction. This enables powerful multimodal AI capabilities in your applications.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Modern LLMs can process more than just text - they can analyze images, extract content from PDFs, and process various file formats. Raif provides a unified interface for working with multimodal content through:

- **`Raif::ModelImageInput`**: For image files and visual content
- **`Raif::ModelFileInput`**: For PDFs, documents, and other file types
- **ActiveStorage Integration**: Seamless work with Rails file attachments
- **URL Support**: Process files directly from web URLs

### Supported File Types

| Type | Formats | Use Cases |
|------|---------|-----------|
| **Images** | PNG, JPEG, GIF, WebP | Visual analysis, OCR, content description |
| **Documents** | PDF, TXT, MD, DOC, DOCX | Text extraction, summarization, analysis |
| **Data Files** | CSV, JSON, XML | Data analysis, structure understanding |
| **Code Files** | Various extensions | Code review, documentation generation |

---

## Working with Images

### Basic Image Input

```ruby
# From a local file path
image = Raif::ModelImageInput.new(input: "path/to/image.png")

# From a URL
image = Raif::ModelImageInput.new(url: "https://example.com/image.jpg")

# From an ActiveStorage attachment
user = User.find(1)
image = Raif::ModelImageInput.new(input: user.avatar)

# Chat with the LLM about the image
llm = Raif.llm(:open_ai_gpt_4o)
model_completion = llm.chat(messages: [
  { role: "user", content: ["What's in this image?", image] }
])

puts model_completion.response
# => "This image shows a golden retriever sitting in a park..."
```

### Advanced Image Analysis

```ruby
# Multiple images in one conversation
images = [
  Raif::ModelImageInput.new(input: "before.jpg"),
  Raif::ModelImageInput.new(input: "after.jpg")
]

llm = Raif.llm(:open_ai_gpt_4o)
completion = llm.chat(messages: [
  { 
    role: "user", 
    content: [
      "Compare these before and after images. What changes do you notice?",
      *images
    ]
  }
])
```

### Image OCR and Text Extraction

```ruby
# Extract text from an image with handwriting or printed text
document_image = Raif::ModelImageInput.new(input: "scanned_document.png")

llm = Raif.llm(:anthropic_claude_3_5_sonnet)
completion = llm.chat(
  system_prompt: "Extract all text from the provided image. Format it cleanly and preserve the structure.",
  messages: [
    { role: "user", content: ["Please extract the text from this document:", document_image] }
  ]
)

extracted_text = completion.response
```

### Visual Content Analysis

```ruby
# Analyze charts, graphs, or diagrams
chart_image = Raif::ModelImageInput.new(url: "https://example.com/sales-chart.png")

llm = Raif.llm(:open_ai_gpt_4o)
completion = llm.chat(messages: [
  { 
    role: "user", 
    content: [
      "Analyze this sales chart. What trends do you see? Provide specific insights about the data.",
      chart_image
    ]
  }
])
```

---

## Working with Files and PDFs

### Basic File Input

```ruby
# From a local PDF file
file = Raif::ModelFileInput.new(input: "path/to/document.pdf")

# From a URL
file = Raif::ModelFileInput.new(url: "https://example.com/report.pdf")

# From an ActiveStorage attachment
document = Document.find(1)
file = Raif::ModelFileInput.new(input: document.pdf_attachment)

# Analyze the file content
llm = Raif.llm(:open_ai_gpt_4o)
completion = llm.chat(messages: [
  { role: "user", content: ["Summarize the key points from this document:", file] }
])
```

### PDF Processing and Analysis

```ruby
# Comprehensive PDF analysis
pdf_file = Raif::ModelFileInput.new(input: "financial_report.pdf")

llm = Raif.llm(:anthropic_claude_3_5_sonnet)
completion = llm.chat(
  system_prompt: "You are a financial analyst. Analyze documents thoroughly and provide structured insights.",
  messages: [
    { 
      role: "user", 
      content: [
        "Analyze this financial report and provide:\n1. Executive summary\n2. Key financial metrics\n3. Notable trends\n4. Risk factors\n5. Recommendations",
        pdf_file
      ]
    }
  ]
)
```

### Document Comparison

```ruby
# Compare multiple documents
old_contract = Raif::ModelFileInput.new(input: "contract_v1.pdf")
new_contract = Raif::ModelFileInput.new(input: "contract_v2.pdf")

llm = Raif.llm(:open_ai_gpt_4o)
completion = llm.chat(messages: [
  { 
    role: "user", 
    content: [
      "Compare these two contract versions. Highlight the key differences, changes in terms, and any important additions or removals.",
      old_contract,
      new_contract
    ]
  }
])
```

### Structured Data Extraction

```ruby
# Extract structured data from documents
invoice_pdf = Raif::ModelFileInput.new(input: "invoice.pdf")

llm = Raif.llm(:open_ai_gpt_4o)
completion = llm.chat(
  response_format: :json,
  messages: [
    { 
      role: "user", 
      content: [
        "Extract the following information from this invoice and return as JSON: company_name, invoice_number, date, due_date, total_amount, line_items (with description, quantity, unit_price)",
        invoice_pdf
      ]
    }
  ]
)

invoice_data = JSON.parse(completion.response)
```

---

## Using Files in Tasks

### Image Description Task

```ruby
# Create a task that processes images
class Raif::Tasks::ImageDescriptionGeneration < Raif::ApplicationTask
  llm_response_format :html
  llm_temperature 0.3
  
  attr_accessor :description_style, :target_audience
  
  def build_system_prompt
    <<~PROMPT
      You are an expert at describing images in detail. Your descriptions should be:
      - Accurate and objective
      - Rich in visual detail
      - Appropriate for the target audience
      - Written in the requested style
    PROMPT
  end
  
  def build_prompt
    style = description_style || "detailed and professional"
    audience = target_audience || "general audience"
    
    "Please provide a #{style} description of the provided image(s), suitable for #{audience}."
  end
end

# Use the task with images
images = [
  Raif::ModelImageInput.new(input: "product_photo.jpg"),
  Raif::ModelImageInput.new(input: "product_detail.jpg")
]

task = Raif::Tasks::ImageDescriptionGeneration.run(
  creator: current_user,
  images: images,
  description_style: "marketing-focused",
  target_audience: "potential customers"
)

puts task.result
```

### PDF Content Extraction Task

```ruby
# Create a task for PDF processing
class Raif::Tasks::PdfContentExtraction < Raif::ApplicationTask
  llm_response_format :json
  llm_temperature 0.1
  
  attr_accessor :extraction_type, :specific_fields
  
  def build_system_prompt
    <<~PROMPT
      You are a document processing specialist. Extract information accurately and return well-structured JSON.
      
      Always validate that the extracted information matches what's actually in the document.
      If information is not found, use null values rather than making assumptions.
    PROMPT
  end
  
  def build_prompt
    case extraction_type
    when 'metadata'
      "Extract document metadata: title, author, creation_date, page_count, document_type, summary"
    when 'structured_data'
      "Extract the following specific fields as JSON: #{specific_fields.join(', ')}"
    when 'full_content'
      "Extract all text content while preserving structure. Include headings, sections, and formatting cues."
    else
      "Extract key information from this document including main topics, important dates, and action items."
    end
  end
end

# Process a PDF document
pdf_file = Raif::ModelFileInput.new(input: "meeting_minutes.pdf")

task = Raif::Tasks::PdfContentExtraction.run(
  creator: current_user,
  files: [pdf_file],
  extraction_type: 'structured_data',
  specific_fields: ['meeting_date', 'attendees', 'action_items', 'decisions_made']
)

extracted_data = JSON.parse(task.result)
```

---

## ActiveStorage Integration

### Working with Uploaded Files

```ruby
# Assuming you have models with ActiveStorage attachments
class Document < ApplicationRecord
  has_one_attached :file
  has_many_attached :images
end

class User < ApplicationRecord
  has_one_attached :profile_picture
  has_one_attached :resume
end

# Process user's uploaded documents
def analyze_user_documents(user)
  documents = []
  
  # Add resume if present
  if user.resume.attached?
    documents << Raif::ModelFileInput.new(input: user.resume)
  end
  
  # Add profile picture for analysis
  if user.profile_picture.attached?
    documents << Raif::ModelImageInput.new(input: user.profile_picture)
  end
  
  return "No documents to analyze" if documents.empty?
  
  llm = Raif.llm(:open_ai_gpt_4o)
  completion = llm.chat(messages: [
    { 
      role: "user", 
      content: [
        "Analyze these user documents and provide insights about their professional background and qualifications:",
        *documents
      ]
    }
  ])
  
  completion.response
end
```

### File Upload and Processing Workflow

```ruby
# Controller for handling file uploads and AI processing
class DocumentAnalysisController < ApplicationController
  def create
    @document = Document.new(document_params)
    
    if @document.save
      # Process the uploaded file with AI
      ProcessDocumentJob.perform_later(@document)
      
      render json: { 
        status: 'uploaded', 
        document_id: @document.id,
        message: 'Document uploaded and processing started'
      }
    else
      render json: { errors: @document.errors }, status: :unprocessable_entity
    end
  end
  
  def show
    @document = Document.find(params[:id])
    
    render json: {
      id: @document.id,
      filename: @document.file.filename,
      processing_status: @document.processing_status,
      analysis_result: @document.analysis_result
    }
  end
  
  private
  
  def document_params
    params.require(:document).permit(:file, :analysis_type)
  end
end

# Background job for processing documents
class ProcessDocumentJob < ApplicationJob
  def perform(document)
    document.update!(processing_status: 'processing')
    
    begin
      file_input = Raif::ModelFileInput.new(input: document.file)
      
      # Choose processing based on document type
      task_class = case document.analysis_type
      when 'summarization'
        Raif::Tasks::DocumentSummarization
      when 'data_extraction'
        Raif::Tasks::PdfContentExtraction
      when 'content_analysis'
        Raif::Tasks::ContentAnalysis
      else
        Raif::Tasks::GeneralDocumentAnalysis
      end
      
      task = task_class.run(
        creator: document.user,
        files: [file_input]
      )
      
      document.update!(
        processing_status: 'completed',
        analysis_result: task.result
      )
      
      # Notify user of completion
      DocumentAnalysisMailer.analysis_complete(document).deliver_now
      
    rescue => e
      document.update!(
        processing_status: 'failed',
        error_message: e.message
      )
      
      # Notify admin of failure
      AdminMailer.document_processing_failed(document, e).deliver_now
    end
  end
end
```

---

## Advanced Use Cases

### Multi-Modal Conversations

Combine text, images, and files in ongoing conversations:

```ruby
# Create a conversation that can handle multiple media types
conversation = Raif::Conversation.create!(
  title: "Document Review Session",
  creator: current_user
)

# Start with a PDF document
pdf_file = Raif::ModelFileInput.new(input: "contract_draft.pdf")
conversation.add_entry!(
  role: :user,
  content: ["Please review this contract draft and highlight any concerning clauses:", pdf_file]
)

response1 = conversation.process_next_entry!

# Follow up with an image
chart_image = Raif::ModelImageInput.new(input: "financial_projections.png")
conversation.add_entry!(
  role: :user,
  content: ["Based on the contract you just reviewed, how do these financial projections align with the terms?", chart_image]
)

response2 = conversation.process_next_entry!

# Continue with text-only follow-up
conversation.add_entry!(
  role: :user,
  content: "What would you recommend changing in the contract based on both documents?"
)

final_response = conversation.process_next_entry!
```

### Batch File Processing

Process multiple files efficiently:

```ruby
# Process multiple documents in batch
class BatchDocumentProcessor
  def initialize(documents, processing_type = 'analysis')
    @documents = documents
    @processing_type = processing_type
  end
  
  def process_all
    results = []
    
    @documents.each_slice(5) do |batch|
      # Process up to 5 documents at once
      file_inputs = batch.map { |doc| Raif::ModelFileInput.new(input: doc.file) }
      
      llm = Raif.llm(:open_ai_gpt_4o)
      completion = llm.chat(
        system_prompt: build_batch_system_prompt,
        messages: [
          { 
            role: "user", 
            content: [
              "Process these documents according to the instructions:",
              *file_inputs
            ]
          }
        ],
        response_format: :json
      )
      
      batch_results = JSON.parse(completion.response)
      results.concat(batch_results)
    end
    
    results
  end
  
  private
  
  def build_batch_system_prompt
    case @processing_type
    when 'summarization'
      "Summarize each document provided. Return an array of objects with filename and summary fields."
    when 'classification'
      "Classify each document by type and content. Return an array with filename, document_type, and category fields."
    when 'extraction'
      "Extract key data from each document. Return an array with filename and extracted_data fields."
    else
      "Analyze each document and provide insights. Return an array with filename and analysis fields."
    end
  end
end

# Usage
documents = Document.where(processing_status: 'pending')
processor = BatchDocumentProcessor.new(documents, 'summarization')
results = processor.process_all
```

### Image and Document Analysis Agent

Create an agent specialized in visual and document analysis:

```ruby
class Raif::Agents::DocumentAnalyst < Raif::Agent
  available_model_tools [
    'Raif::ModelTools::FileProcessor',
    'Raif::ModelTools::ImageAnalyzer',
    'Raif::ModelTools::DataExtractor'
  ]
  
  llm_temperature 0.1
  max_iterations 8
  
  def build_system_prompt
    <<~PROMPT
      You are a document and image analysis specialist. You can:
      - Analyze PDF documents for content, structure, and key information
      - Process images for OCR, visual content analysis, and data extraction
      - Compare multiple documents or images
      - Extract structured data from various file formats
      
      For each analysis task:
      1. First, examine the provided files to understand their type and content
      2. Use appropriate tools to process the files based on their format
      3. Provide detailed analysis with specific findings
      4. Suggest actionable insights or next steps
      
      Always be thorough and cite specific examples from the source materials.
    PROMPT
  end
end

# Use the agent for complex document analysis
agent = Raif::Agents::DocumentAnalyst.new(
  instructions: "Analyze the uploaded financial statements and market research report. Compare the findings and provide investment recommendations."
)

# The agent can process multiple file types and provide comprehensive analysis
result = agent.run!
```

---

## Best Practices

### File Size and Format Optimization

<div class="callout callout-info">
<div class="callout-title">💡 Optimization Tips</div>
<ul>
<li><strong>Image formats</strong>: Use PNG for text/diagrams, JPEG for photos</li>
<li><strong>File sizes</strong>: Keep images under 20MB, PDFs under 100MB when possible</li>
<li><strong>Resolution</strong>: Higher resolution improves OCR accuracy but increases processing time</li>
<li><strong>PDF optimization</strong>: Text-based PDFs work better than scanned images</li>
</ul>
</div>

### Error Handling

```ruby
def safe_file_processing(file_path)
  begin
    # Validate file exists and is readable
    raise "File not found: #{file_path}" unless File.exist?(file_path)
    raise "File too large" if File.size(file_path) > 50.megabytes
    
    # Create appropriate input based on file type
    file_input = case File.extname(file_path).downcase
    when '.png', '.jpg', '.jpeg', '.gif', '.webp'
      Raif::ModelImageInput.new(input: file_path)
    when '.pdf', '.doc', '.docx', '.txt'
      Raif::ModelFileInput.new(input: file_path)
    else
      raise "Unsupported file type: #{File.extname(file_path)}"
    end
    
    # Process the file
    llm = Raif.llm(:open_ai_gpt_4o)
    completion = llm.chat(messages: [
      { role: "user", content: ["Analyze this file:", file_input] }
    ])
    
    { success: true, result: completion.response }
    
  rescue => e
    Rails.logger.error "File processing failed: #{e.message}"
    { success: false, error: e.message }
  end
end
```

### Security Considerations

<div class="callout callout-warning">
<div class="callout-title">⚠️ Security Guidelines</div>
<ul>
<li><strong>File validation</strong>: Always validate file types and sizes before processing</li>
<li><strong>Sensitive data</strong>: Be cautious when sending sensitive documents to external LLM providers</li>
<li><strong>Access control</strong>: Implement proper authorization for file access and processing</li>
<li><strong>Data retention</strong>: Consider LLM provider data retention policies for sensitive files</li>
</ul>
</div>

### Performance Optimization

```ruby
# Cache frequently accessed file analyses
class CachedFileAnalyzer
  def self.analyze(file_input, analysis_type = 'general')
    cache_key = generate_cache_key(file_input, analysis_type)
    
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      llm = Raif.llm(:open_ai_gpt_4o)
      completion = llm.chat(
        system_prompt: system_prompt_for_type(analysis_type),
        messages: [
          { role: "user", content: ["Analyze this file:", file_input] }
        ]
      )
      
      {
        analysis: completion.response,
        analyzed_at: Time.current,
        model_used: completion.model_key
      }
    end
  end
  
  private
  
  def self.generate_cache_key(file_input, analysis_type)
    file_hash = case file_input
    when Raif::ModelImageInput
      Digest::MD5.file(file_input.input.path) if file_input.input.respond_to?(:path)
    when Raif::ModelFileInput
      Digest::MD5.file(file_input.input.path) if file_input.input.respond_to?(:path)
    end
    
    "file_analysis:#{analysis_type}:#{file_hash}"
  end
end
```

Images, files, and PDFs open up powerful multimodal capabilities in your AI applications, enabling rich document processing, visual analysis, and comprehensive content understanding! 