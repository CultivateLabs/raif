---
layout: default
title: Demo App
nav_order: 12
description: "Explore the Raif demo application to see the framework in action"
---

# Demo App
{: .no_toc }

The Raif demo application showcases all major features of the framework in a working Rails application. It's the perfect way to explore Raif's capabilities, test different LLM providers, and see real examples of tasks, conversations, and agents in action.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The [Raif Demo App](https://github.com/CultivateLabs/raif_demo) is a complete Rails application that demonstrates every aspect of the Raif framework. It includes:

- **Interactive Examples**: Working demonstrations of tasks, conversations, and agents
- **Multiple LLM Providers**: Test OpenAI, Anthropic, AWS Bedrock, and OpenRouter
- **Real-World Use Cases**: Practical examples you can adapt for your applications
- **Admin Interface**: Full access to the Raif web admin for monitoring AI interactions
- **Testing Examples**: Complete test suite showing testing best practices

### Key Features Demonstrated

- **Document Analysis**: PDF processing and summarization
- **Customer Support Chat**: Multi-turn conversations with context
- **Research Agent**: ReAct-style agent using multiple tools
- **Image Analysis**: Visual content processing and OCR
- **Data Processing**: Structured data analysis and insights
- **Tool Integration**: Custom model tools for external services

<div class="callout callout-info">
<div class="callout-title">💡 Perfect for Learning</div>
The demo app is designed as both a showcase and a learning resource. Each feature includes detailed code examples, comments explaining the implementation, and links to relevant documentation sections.
</div>

---

## Quick Start

### Prerequisites

Before running the demo app, ensure you have:

- **Ruby 3.4.2+** (check with `ruby --version`)
- **PostgreSQL** (or SQLite for development)
- **Git** for cloning the repository
- **An API key** for at least one LLM provider

### Installation

Clone and set up the demo app:

```bash
# Clone the repository
git clone git@github.com:CultivateLabs/raif_demo.git
cd raif_demo

# Install dependencies
bundle install

# Set up the database
bin/rails db:create db:prepare

# Start the server with your API key
OPENAI_API_KEY=your-openai-api-key-here bin/rails s
```

<div class="callout callout-success">
<div class="callout-title">✅ Quick Setup</div>
The demo app includes seed data and example configurations, so you can start exploring immediately after setup. No additional configuration is required for basic usage.
</div>

### Accessing the Application

Once running, you can access:

- **Main Demo**: [http://localhost:3000](http://localhost:3000)
- **Admin Interface**: [http://localhost:3000/raif/admin](http://localhost:3000/raif/admin)
- **API Documentation**: [http://localhost:3000/api/docs](http://localhost:3000/api/docs)

---

## Demo Features

### 1. Document Processing

The demo includes a complete document processing workflow:

```ruby
# Example: Document Summarization Task
class Raif::Tasks::DocumentSummarization < Raif::ApplicationTask
  llm_response_format :html
  llm_temperature 0.3
  
  attr_accessor :document, :summary_type
  
  def build_system_prompt
    "You are an expert document analyzer capable of creating clear, " \
    "concise summaries while preserving key information and insights."
  end
  
  def build_prompt
    content = document.content.presence || "No content available"
    type = summary_type || "general"
    
    case type
    when "executive"
      "Create an executive summary of this document focusing on key decisions, " \
      "recommendations, and action items:\n\n#{content}"
    when "technical"
      "Create a technical summary highlighting methodologies, findings, " \
      "and technical details:\n\n#{content}"
    else
      "Create a comprehensive summary of this document:\n\n#{content}"
    end
  end
end
```

**Demo Features:**
- Upload PDF documents and text files
- Choose from different summary types (executive, technical, general)
- Real-time processing with progress indicators
- Side-by-side view of original and summary
- Export results in multiple formats

### 2. Customer Support Chat

Experience a complete customer support conversation system:

```ruby
# Example: Support Conversation
class Raif::Conversations::CustomerSupport < Raif::Conversation
  def build_system_prompt
    user_context = creator&.name ? " with #{creator.name}" : ""
    
    <<~PROMPT
      You are a helpful customer support representative#{user_context}. 
      
      Guidelines:
      - Be empathetic and professional
      - Ask clarifying questions when needed
      - Provide step-by-step solutions
      - Escalate complex technical issues appropriately
      - Reference relevant documentation when helpful
      
      Today's date: #{Date.current.strftime('%B %d, %Y')}
    PROMPT
  end
  
  # Custom logic for support ticket creation
  def create_support_ticket_if_needed(entry_content)
    if entry_content.downcase.include?("bug") || 
       entry_content.downcase.include?("error") ||
       entry_content.downcase.include?("not working")
      
      SupportTicket.create!(
        conversation: self,
        creator: creator,
        title: extract_issue_title(entry_content),
        priority: determine_priority(entry_content),
        status: 'open'
      )
    end
  end
end
```

**Demo Features:**
- Live chat interface with typing indicators
- Conversation history and context preservation
- Automatic support ticket creation for issues
- Sentiment analysis and satisfaction tracking
- Integration with help desk systems

### 3. Research Assistant Agent

Watch a ReAct-style agent conduct research using multiple tools:

```ruby
# Example: Research Agent
class Raif::Agents::ResearchAssistant < Raif::Agent
  available_model_tools [
    'Raif::ModelTools::WikipediaSearch',
    'Raif::ModelTools::WebSearch',
    'Raif::ModelTools::FetchUrl',
    'Raif::ModelTools::DataAnalyzer'
  ]
  
  max_iterations 8
  llm_temperature 0.1
  
  def build_system_prompt
    <<~PROMPT
      You are an expert research assistant. Your goal is to conduct thorough 
      research on any given topic using the available tools.
      
      Research Process:
      1. Start with broad searches to understand the topic
      2. Use specific tools to gather detailed information
      3. Analyze and synthesize findings
      4. Provide a comprehensive, well-structured report
      
      Available Tools:
      - wikipedia_search: For encyclopedic information
      - web_search: For current information and diverse sources
      - fetch_url: To read specific web pages in detail
      - data_analyzer: To process and analyze data
      
      Always cite your sources and be transparent about limitations.
    PROMPT
  end
  
  def process_iteration_model_completion(model_completion)
    super
    
    # Custom logic for research progress tracking
    if current_iteration_thinking.include?("sufficient information")
      update_research_progress(85)
    elsif current_iteration_thinking.include?("need more data")
      update_research_progress(40)
    end
  end
end
```

**Demo Features:**
- Step-by-step reasoning visualization
- Real-time tool usage tracking
- Research progress indicators
- Source citation and verification
- Downloadable research reports

### 4. Image Analysis Workflows

Explore multimodal AI capabilities:

```ruby
# Example: Image Analysis Task
class Raif::Tasks::ImageAnalysis < Raif::ApplicationTask
  llm_response_format :json
  llm_temperature 0.2
  
  attr_accessor :analysis_type, :detail_level
  
  def build_system_prompt
    <<~PROMPT
      You are an expert image analyst capable of detailed visual analysis.
      
      Provide analysis in the following JSON format:
      {
        "description": "Detailed description of the image",
        "objects": ["list", "of", "identified", "objects"],
        "text_content": "Any text found in the image",
        "analysis": "Specific analysis based on the requested type",
        "confidence": 0.95,
        "metadata": {
          "colors": ["dominant", "colors"],
          "composition": "Description of visual composition"
        }
      }
    PROMPT
  end
  
  def build_prompt
    type = analysis_type || "general"
    detail = detail_level || "medium"
    
    case type
    when "chart"
      "Analyze this chart or graph. Extract data points, trends, and insights."
    when "document"
      "Perform OCR on this document. Extract all text and analyze the document structure."
    when "product"
      "Analyze this product image for marketing insights, features, and quality assessment."
    else
      "Provide a #{detail} analysis of this image including all visible elements and their significance."
    end
  end
end
```

**Demo Features:**
- Drag-and-drop image upload
- Multiple analysis types (charts, documents, products)
- OCR text extraction with formatting
- Visual element identification
- Batch processing capabilities

### 5. Data Analysis Pipeline

See structured data processing in action:

```ruby
# Example: Data Analysis Agent
class Raif::Agents::DataAnalyst < Raif::Agent
  available_model_tools [
    'Raif::ModelTools::DatabaseQuery',
    'Raif::ModelTools::DataProcessor',
    'Raif::ModelTools::ChartGenerator',
    'Raif::ModelTools::StatisticalAnalyzer'
  ]
  
  def build_system_prompt
    <<~PROMPT
      You are a senior data analyst with expertise in:
      - Statistical analysis and interpretation
      - Data visualization and reporting
      - Pattern recognition and trend analysis
      - Business intelligence and insights
      
      Your analysis should always include:
      1. Executive summary of findings
      2. Detailed statistical analysis
      3. Visual representations where helpful
      4. Actionable recommendations
      5. Confidence levels and limitations
    PROMPT
  end
end
```

**Demo Features:**
- Interactive data upload (CSV, JSON, Excel)
- Automated statistical analysis
- Dynamic chart generation
- Insight extraction and reporting
- Export to multiple formats

---

## Demo App Architecture

### File Structure

The demo app follows Rails conventions with Raif-specific organization:

```
raif_demo/
├── app/
│   ├── models/
│   │   ├── raif/
│   │   │   ├── tasks/
│   │   │   │   ├── document_summarization.rb
│   │   │   │   ├── image_analysis.rb
│   │   │   │   └── data_processing.rb
│   │   │   ├── conversations/
│   │   │   │   ├── customer_support.rb
│   │   │   │   └── research_chat.rb
│   │   │   ├── agents/
│   │   │   │   ├── research_assistant.rb
│   │   │   │   └── data_analyst.rb
│   │   │   └── model_tools/
│   │   │       ├── web_search.rb
│   │   │       ├── data_processor.rb
│   │   │       └── chart_generator.rb
│   │   ├── user.rb
│   │   ├── document.rb
│   │   └── support_ticket.rb
│   ├── controllers/
│   │   ├── demo_controller.rb
│   │   ├── documents_controller.rb
│   │   └── api/
│   │       └── v1/
│   └── views/
│       ├── demo/
│       ├── shared/
│       └── layouts/
├── config/
│   ├── initializers/
│   │   └── raif.rb
│   └── routes.rb
├── spec/
│   ├── models/
│   ├── requests/
│   └── system/
└── README.md
```

### Configuration Examples

The demo app shows various configuration patterns:

```ruby
# config/initializers/raif.rb
Raif.configure do |config|
  # Multi-provider setup
  config.open_ai_models_enabled = ENV['OPENAI_API_KEY'].present?
  config.anthropic_models_enabled = ENV['ANTHROPIC_API_KEY'].present?
  config.bedrock_models_enabled = ENV['AWS_REGION'].present?
  
  # Dynamic model selection based on availability
  config.default_llm_model_key = if ENV['OPENAI_API_KEY'].present?
    'open_ai_gpt_4o'
  elsif ENV['ANTHROPIC_API_KEY'].present?
    'anthropic_claude_3_5_sonnet'
  else
    'open_router_claude_3_5_sonnet'
  end
  
  # Demo-specific settings
  config.enable_conversation_rating = true
  config.max_conversation_entries = 100
  config.conversation_context_window = 20
  
  # Authorization for demo (simplified for development)
  config.authorize_controller_action = -> { true }
  config.authorize_admin_controller_action = -> { true }
end
```

---

## Running the Demo

### Environment Setup

Configure your environment for the best demo experience:

```bash
# .env file for development
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here
AWS_REGION=us-east-1
OPENROUTER_API_KEY=your_openrouter_key_here

# Optional: Configure specific models
RAIF_DEFAULT_MODEL=open_ai_gpt_4o
RAIF_FAST_MODEL=open_ai_gpt_3_5_turbo
RAIF_ANALYSIS_MODEL=anthropic_claude_3_5_sonnet

# Demo-specific settings
DEMO_ENABLE_FILE_UPLOAD=true
DEMO_MAX_FILE_SIZE=50MB
DEMO_ENABLE_REAL_TIME_UPDATES=true
```

### Development Server

Start the demo with various options:

```bash
# Basic startup
bin/rails server

# With specific model
RAIF_DEFAULT_MODEL=anthropic_claude_3_5_sonnet bin/rails s

# With debug logging
RAIF_DEBUG=true bin/rails s

# Production-like environment
RAILS_ENV=production bin/rails s
```

### Docker Setup (Alternative)

Run the demo using Docker:

```bash
# Clone and build
git clone git@github.com:CultivateLabs/raif_demo.git
cd raif_demo

# Build and run with Docker Compose
docker-compose up --build

# Access at http://localhost:3000
```

```yaml
# docker-compose.yml (example)
version: '3.8'
services:
  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - DATABASE_URL=postgresql://postgres:password@db:5432/raif_demo
    depends_on:
      - db
    volumes:
      - .:/app
      
  db:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=raif_demo
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

---

## Demo Scenarios

### Scenario 1: Document Processing Workflow

1. **Upload Document**: Upload a PDF or text file
2. **Choose Analysis Type**: Select from summarization, analysis, or extraction
3. **Configure Options**: Set detail level, format, and language
4. **Process Document**: Watch real-time processing with progress updates
5. **Review Results**: See formatted output with source citations
6. **Export/Share**: Download results or share via link

### Scenario 2: Customer Support Simulation

1. **Start Chat**: Begin a customer support conversation
2. **Ask Questions**: Simulate common customer issues
3. **Experience AI**: See context-aware responses and problem-solving
4. **Escalation**: Trigger automatic ticket creation for complex issues
5. **Review Admin**: Check the admin interface for conversation logs
6. **Rate Experience**: Provide feedback on the AI's performance

### Scenario 3: Research Project

1. **Define Topic**: Enter a research topic or question
2. **Launch Agent**: Start the research assistant agent
3. **Watch Process**: Observe step-by-step reasoning and tool usage
4. **Real-time Updates**: See live progress as the agent works
5. **Review Report**: Get comprehensive findings with sources
6. **Download Results**: Export formatted research report

### Scenario 4: Image Analysis Pipeline

1. **Upload Images**: Add single or multiple images
2. **Select Analysis**: Choose from OCR, content analysis, or chart reading
3. **Configure Settings**: Set detail level and specific requirements
4. **Process Batch**: Watch parallel processing of multiple images
5. **Compare Results**: Review analysis across different images
6. **Extract Data**: Export structured data from the analysis

---

## Exploring the Code

### Task Examples

The demo includes comprehensive task examples:

```ruby
# app/models/raif/tasks/pdf_analysis.rb
class Raif::Tasks::PdfAnalysis < Raif::ApplicationTask
  llm_response_format :json
  llm_temperature 0.1
  
  attr_accessor :pdf_file, :analysis_focus
  
  def build_system_prompt
    "You are a document analysis expert. Analyze PDF documents and extract structured information."
  end
  
  def build_prompt
    focus = analysis_focus || "general"
    
    case focus
    when "financial"
      "Analyze this financial document. Extract key metrics, dates, and financial data."
    when "legal"
      "Analyze this legal document. Identify clauses, obligations, and key terms."
    when "technical"
      "Analyze this technical document. Extract specifications, procedures, and requirements."
    else
      "Provide a comprehensive analysis of this document including structure, content, and key insights."
    end
  end
end
```

### Conversation Examples

See different conversation types:

```ruby
# app/models/raif/conversations/research_chat.rb
class Raif::Conversations::ResearchChat < Raif::Conversation
  def build_system_prompt
    <<~PROMPT
      You are a research assistant helping with academic and professional research.
      
      Capabilities:
      - Literature review and citation
      - Methodology guidance
      - Data interpretation
      - Research design advice
      
      Always ask for clarification when research topics are broad.
      Provide specific, actionable guidance.
    PROMPT
  end
end
```

### Agent Examples

Study agent implementations:

```ruby
# app/models/raif/agents/content_creator.rb
class Raif::Agents::ContentCreator < Raif::Agent
  available_model_tools [
    'Raif::ModelTools::WebSearch',
    'Raif::ModelTools::ImageGenerator',
    'Raif::ModelTools::ContentOptimizer'
  ]
  
  def build_system_prompt
    "You are a content creation specialist. Use available tools to research, create, and optimize content."
  end
end
```

---

## Testing the Demo

The demo app includes comprehensive tests:

```ruby
# spec/system/demo_features_spec.rb
RSpec.describe "Demo Features", type: :system do
  it "demonstrates document processing workflow" do
    visit root_path
    
    click_link "Document Processing"
    attach_file "document", file_fixture("sample.pdf")
    select "Executive Summary", from: "summary_type"
    click_button "Process Document"
    
    expect(page).to have_content("Processing complete")
    expect(page).to have_css(".summary-result")
  end
  
  it "shows conversation interface" do
    visit conversations_path
    
    click_link "Start New Chat"
    fill_in "message", with: "Hello, I need help with my account"
    click_button "Send"
    
    expect(page).to have_css(".conversation-entry.assistant")
    expect(page).to have_content("I'd be happy to help")
  end
end
```

---

## Advanced Features

### Real-time Updates

The demo showcases real-time features:

```javascript
// app/javascript/controllers/demo_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progress", "result", "status"]
  
  connect() {
    this.connectWebSocket()
  }
  
  connectWebSocket() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "DemoChannel", demo_id: this.data.get("demoId") },
      {
        received: (data) => {
          this.updateProgress(data.progress)
          if (data.result) {
            this.showResult(data.result)
          }
        }
      }
    )
  }
  
  updateProgress(progress) {
    this.progressTarget.style.width = `${progress}%`
    this.statusTarget.textContent = `Processing... ${progress}%`
  }
}
```

### Performance Monitoring

Built-in performance tracking:

```ruby
# app/models/demo_analytics.rb
class DemoAnalytics
  def self.track_usage(feature, user, duration, success)
    Rails.logger.info({
      event: "demo_feature_used",
      feature: feature,
      user_id: user&.id,
      duration_ms: duration,
      success: success,
      timestamp: Time.current
    }.to_json)
  end
  
  def self.generate_report
    {
      total_interactions: Raif::ModelCompletion.count,
      average_response_time: Raif::ModelCompletion.average(:response_time_ms),
      success_rate: calculate_success_rate,
      popular_features: calculate_feature_usage
    }
  end
end
```

---

## Deployment Guide

### Production Deployment

Deploy the demo app to production:

```bash
# Heroku deployment
heroku create raif-demo-app
heroku addons:create heroku-postgresql
heroku config:set OPENAI_API_KEY=your_key_here
heroku config:set RAILS_MASTER_KEY=your_master_key
git push heroku main
heroku run rails db:migrate
```

### Environment Variables

Required for production:

```bash
# Essential keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
AWS_REGION=us-east-1

# Application settings
RAILS_MASTER_KEY=your_master_key
DATABASE_URL=postgresql://...
REDIS_URL=redis://...

# Raif-specific settings
RAIF_DEFAULT_MODEL=open_ai_gpt_4o
RAIF_ENABLE_CACHING=true
RAIF_MAX_FILE_SIZE=50MB
```

<div class="callout callout-warning">
<div class="callout-title">⚠️ Security Note</div>
The demo app includes simplified authentication for demonstration purposes. For production deployment, implement proper user authentication, authorization, and security measures.
</div>

The Raif demo app provides a comprehensive showcase of the framework's capabilities, making it easy to understand and explore all features before implementing them in your own applications! 