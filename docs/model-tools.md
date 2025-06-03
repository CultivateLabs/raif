---
layout: default
title: Model Tools
nav_order: 6
description: "Custom tools that AI models can invoke"
---

# Model Tools
{: .no_toc }

Custom functions that AI models can invoke to perform tasks like database queries, API calls, calculations, or other operations.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Model Tools allow LLMs to interact with your application's data and services beyond text generation.

### Key Features
- **Structured Arguments**: Define schemas for tool inputs
- **Return Structured Data**: Tools return JSON-serializable results
- **Error Handling**: Built-in error management and recovery
- **Usage Tracking**: Automatic logging of tool invocations

### Tool Types
1. **Custom Tools**: Built by you for application-specific functionality
2. **Provider-Managed Tools**: Built-in tools that run on LLM provider infrastructure

---

## Creating Custom Tools

```bash
rails generate raif:model_tool WeatherLookup
```

```ruby
class Raif::ModelTools::WeatherLookup < Raif::ModelTool
  tool_arguments_schema do
    string :location, description: "City and state or country"
    string :date, description: "Date for weather lookup (YYYY-MM-DD format)", required: false
  end
  
  def self.process_invocation(tool_invocation)
    location = tool_invocation.tool_arguments["location"]
    date = tool_invocation.tool_arguments["date"] || Date.current.to_s
    
    weather_data = WeatherService.fetch_weather(location, date)
    
    if weather_data
      {
        success: true,
        location: location,
        date: date,
        temperature: weather_data.temperature,
        conditions: weather_data.conditions,
        humidity: weather_data.humidity
      }
    else
      {
        success: false,
        error: "Could not fetch weather data for #{location}"
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: "Weather service error: #{e.message}"
    }
  end
  
  def self.observation_for_invocation(tool_invocation)
    result = tool_invocation.raif_model_tool_invocation_result&.result_data
    
    if result&.dig("success")
      <<~OBSERVATION
        Weather for #{result['location']} on #{result['date']}:
        Temperature: #{result['temperature']}°F
        Conditions: #{result['conditions']}
        Humidity: #{result['humidity']}%
      OBSERVATION
    else
      "Weather lookup failed: #{result&.dig('error') || 'Unknown error'}"
    end
  end
end
```

---

## Tool Arguments Schema

### Basic Types

```ruby
class Raif::ModelTools::UserLookup < Raif::ModelTool
  tool_arguments_schema do
    string :email, description: "User's email address"
    integer :user_id, description: "User's ID number", required: false
    boolean :include_profile, description: "Include full profile data", required: false
  end
end
```

### Advanced Schema

```ruby
class Raif::ModelTools::DataQuery < Raif::ModelTool
  tool_arguments_schema do
    string :table_name, 
           description: "Name of the database table to query",
           enum: ["users", "orders", "products"]
    
    string :query_type,
           description: "Type of query to perform", 
           enum: ["count", "select", "aggregate"]
    
    object :filters, description: "Query filters" do
      string :status, required: false
      integer :limit, description: "Maximum results to return", required: false
      date :created_after, description: "Filter by creation date", required: false
    end
    
    array :columns, 
          description: "Columns to include in results",
          items: { type: "string" },
          required: false
  end
end
```

---

## Example Tools

### Database Query Tool

```ruby
class Raif::ModelTools::DatabaseQuery < Raif::ModelTool
  tool_arguments_schema do
    string :query, description: "SQL query to execute (SELECT only)"
    integer :limit, description: "Maximum rows to return", required: false
  end
  
  def self.process_invocation(tool_invocation)
    query = tool_invocation.tool_arguments["query"]
    limit = tool_invocation.tool_arguments["limit"] || 100
    
    # Security: Only allow SELECT queries
    unless query.strip.downcase.start_with?("select")
      return {
        success: false,
        error: "Only SELECT queries are allowed"
      }
    end
    
    # Add LIMIT if not present
    unless query.downcase.include?("limit")
      query += " LIMIT #{limit}"
    end
    
    begin
      results = ActiveRecord::Base.connection.execute(query).to_a
      
      {
        success: true,
        query: query,
        row_count: results.length,
        results: results
      }
    rescue ActiveRecord::StatementInvalid => e
      {
        success: false,
        error: "SQL Error: #{e.message}"
      }
    end
  end
  
  def self.observation_for_invocation(tool_invocation)
    result = tool_invocation.raif_model_tool_invocation_result&.result_data
    
    if result&.dig("success")
      rows = result["results"]
      <<~OBSERVATION
        Database query executed successfully:
        Query: #{result['query']}
        Returned #{result['row_count']} rows
        
        Sample results:
        #{rows.first(3).map { |row| row.to_s }.join("\n")}
        #{rows.length > 3 ? "... and #{rows.length - 3} more rows" : ""}
      OBSERVATION
    else
      "Database query failed: #{result&.dig('error')}"
    end
  end
end
```

### API Integration Tool

```ruby
class Raif::ModelTools::SlackNotification < Raif::ModelTool
  tool_arguments_schema do
    string :channel, description: "Slack channel name (without #)"
    string :message, description: "Message to send"
    string :urgency, description: "Message urgency level", enum: ["low", "normal", "high"], required: false
  end
  
  def self.process_invocation(tool_invocation)
    channel = tool_invocation.tool_arguments["channel"]
    message = tool_invocation.tool_arguments["message"] 
    urgency = tool_invocation.tool_arguments["urgency"] || "normal"
    
    formatted_message = case urgency
                       when "high"
                         "🚨 URGENT: #{message}"
                       when "low"
                         "ℹ️ #{message}"
                       else
                         message
                       end
    
    begin
      response = SlackService.send_message(
        channel: "##{channel}",
        text: formatted_message
      )
      
      {
        success: true,
        channel: channel,
        message_id: response["ts"],
        permalink: response["permalink"]
      }
    rescue SlackService::Error => e
      {
        success: false,
        error: "Slack API error: #{e.message}"
      }
    end
  end
  
  def self.observation_for_invocation(tool_invocation)
    result = tool_invocation.raif_model_tool_invocation_result&.result_data
    
    if result&.dig("success")
      "Message sent successfully to ##{result['channel']}. Message ID: #{result['message_id']}"
    else
      "Failed to send Slack message: #{result&.dig('error')}"
    end
  end
end
```

---

## Provider-Managed Tools

Raif includes provider-managed tools that run on LLM provider infrastructure:

```ruby
# Web Search
class Raif::ModelTools::ProviderManaged::WebSearch < Raif::ModelTool
  # Implemented by the LLM provider
end

# Code Execution
class Raif::ModelTools::ProviderManaged::CodeExecution < Raif::ModelTool
  # Execute code in sandboxed environments
end

# Image Generation
class Raif::ModelTools::ProviderManaged::ImageGeneration < Raif::ModelTool
  # Generate images from text descriptions
end
```

---

## Using Tools

### In Tasks

```ruby
task = Raif::Tasks::DataAnalysis.run(
  query: "How many users signed up last month?",
  creator: current_user,
  available_model_tools: [
    "Raif::ModelTools::DatabaseQuery",
    "Raif::ModelTools::ChartGenerator"
  ]
)
```

### In Conversations

```ruby
class Raif::Conversations::DataAssistant < Raif::ApplicationConversation
  before_create -> {
    self.available_model_tools = [
      "Raif::ModelTools::DatabaseQuery",
      "Raif::ModelTools::CsvProcessor",
      "Raif::ModelTools::StatisticalAnalysis"
    ]
  }
end
```

### In Agents

```ruby
class Raif::Agents::BusinessAnalyst < Raif::ApplicationAgent
  before_create -> {
    self.available_model_tools = [
      "Raif::ModelTools::DatabaseQuery",
      "Raif::ModelTools::ProviderManaged::WebSearch",
      "Raif::ModelTools::ReportGenerator"
    ]
  }
end
```

---

## Security & Error Handling

### Input Validation

```ruby
class Raif::ModelTools::SecureTool < Raif::ModelTool
  tool_arguments_schema do
    string :input, description: "User input to process"
  end
  
  def self.process_invocation(tool_invocation)
    input = tool_invocation.tool_arguments["input"]
    
    # Validate input
    if input.blank?
      return {
        success: false,
        error: "Input cannot be empty"
      }
    end
    
    # Sanitize input
    cleaned_input = ActionController::Base.helpers.sanitize(input)
    
    {
      success: true,
      processed_input: cleaned_input
    }
  end
end
```

### Access Control

```ruby
class Raif::ModelTools::AdminOnlyTool < Raif::ModelTool
  def self.process_invocation(tool_invocation)
    creator = tool_invocation.source&.creator
    
    unless creator&.admin?
      return {
        success: false,
        error: "Admin access required"
      }
    end
    
    # Process admin-only functionality...
  end
end
```

---

## Testing

```ruby
RSpec.describe Raif::ModelTools::WeatherLookup do
  describe ".process_invocation" do
    let(:tool_invocation) do
      create(:raif_model_tool_invocation,
        tool_name: "weather_lookup",
        tool_arguments: {
          "location" => "San Francisco, CA",
          "date" => "2024-01-15"
        }
      )
    end
    
    it "fetches weather data successfully" do
      weather_data = double(
        temperature: 65,
        conditions: "Partly cloudy",
        humidity: 70
      )
      
      allow(WeatherService).to receive(:fetch_weather)
        .with("San Francisco, CA", "2024-01-15")
        .and_return(weather_data)
      
      result = described_class.process_invocation(tool_invocation)
      
      expect(result[:success]).to be(true)
      expect(result[:temperature]).to eq(65)
      expect(result[:conditions]).to eq("Partly cloudy")
    end
    
    it "handles API failures gracefully" do
      allow(WeatherService).to receive(:fetch_weather)
        .and_raise(WeatherService::ApiError, "Service unavailable")
      
      result = described_class.process_invocation(tool_invocation)
      
      expect(result[:success]).to be(false)
      expect(result[:error]).to include("Service unavailable")
    end
  end
  
  describe ".observation_for_invocation" do
    it "formats successful results for LLM consumption" do
      tool_invocation = create(:raif_model_tool_invocation)
      create(:raif_model_tool_invocation_result,
        raif_model_tool_invocation: tool_invocation,
        result_data: {
          success: true,
          location: "San Francisco, CA",
          temperature: 65,
          conditions: "Sunny"
        }
      )
      
      observation = described_class.observation_for_invocation(tool_invocation)
      
      expect(observation).to include("San Francisco, CA")
      expect(observation).to include("65°F")
      expect(observation).to include("Sunny")
    end
  end
end
``` 