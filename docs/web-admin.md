---
layout: default
title: Web Admin
nav_order: 8
description: "Administrative interface for monitoring and managing Raif interactions"
---

# Web Admin
{: .no_toc }

Raif includes a comprehensive web admin interface for monitoring all AI interactions, analyzing usage patterns, and debugging issues. The admin interface provides detailed insights into your application's AI operations.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The Raif Web Admin interface is your central dashboard for managing and monitoring AI operations in your application. It provides real-time visibility into:

- **Model Completions**: Every interaction with LLM providers
- **Task Executions**: Performance and results of AI tasks
- **Conversation Flows**: Multi-turn chat sessions and their progression
- **Agent Operations**: Detailed logs of agent reasoning and tool usage
- **Model Tool Invocations**: Tool calls and their results
- **Usage Statistics**: Cost analysis, performance metrics, and usage trends

### Key Features

- **Real-Time Monitoring**: Live view of AI operations as they happen
- **Detailed Logging**: Complete audit trail of all AI interactions
- **Performance Analytics**: Response times, token usage, and cost tracking
- **Error Debugging**: Detailed error messages and stack traces
- **Search and Filtering**: Find specific interactions quickly
- **Export Capabilities**: Download data for analysis and reporting

---

## Accessing the Admin Interface

### Setup and Configuration

First, ensure you have configured authorization in your Raif initializer:

```ruby
# config/initializers/raif.rb
Raif.configure do |config|
  # Configure admin access - only allow administrators
  config.authorize_admin_controller_action = -> { current_user&.admin? }
  
  # Or use more specific authorization logic
  config.authorize_admin_controller_action = -> { 
    current_user.present? && (current_user.admin? || current_user.raif_admin?)
  }
end
```

### Accessing the Interface

With the engine mounted at `/raif`, the admin interface is available at:

```
https://yourapp.com/raif/admin
```

<div class="callout callout-warning">
<div class="callout-title">⚠️ Security Note</div>
The admin interface provides access to all AI interactions including potentially sensitive data. Ensure proper authorization is configured and only trusted administrators have access.
</div>

---

## Admin Dashboard Sections

### Model Completions

The Model Completions section shows every interaction with LLM providers:

**Features:**
- **Real-time list** of all LLM API calls
- **Request/response details** with full message content
- **Token usage tracking** and cost calculations
- **Response time monitoring** and performance metrics
- **Error logging** with detailed error messages
- **Provider information** (OpenAI, Anthropic, AWS Bedrock, etc.)

**Filtering Options:**
```ruby
# Filter by date range
/raif/admin/model_completions?start_date=2024-01-01&end_date=2024-01-31

# Filter by LLM provider
/raif/admin/model_completions?llm_provider=openai

# Filter by response format
/raif/admin/model_completions?response_format=json

# Search by content
/raif/admin/model_completions?search=customer%20support
```

**Key Metrics Displayed:**
- Total token usage (input/output)
- Response time in milliseconds
- HTTP status codes and error rates
- Model versions used
- Cost per completion

### Tasks

Monitor all AI task executions and their performance:

**Task Overview:**
- **Task type and status** (pending, processing, completed, failed)
- **Input parameters** and configuration
- **Generated results** and output quality
- **Processing time** and performance metrics
- **Creator information** and audit trail

**Debugging Features:**
- **System prompts** used for each task
- **Complete input/output** for troubleshooting
- **Error messages** and stack traces
- **Model completions** linked to task execution

```ruby
# Example: Viewing task details in admin
class TasksController < ApplicationController
  def show
    @task = Raif::Task.find(params[:id])
    @model_completions = @task.model_completions.order(:created_at)
    @processing_time = @task.completed_at - @task.created_at if @task.completed?
  end
end
```

### Conversations

Detailed view of multi-turn chat interactions:

**Conversation Management:**
- **Complete conversation history** with all entries
- **Participant information** (users, AI responses)
- **Tool usage tracking** during conversations
- **Response quality metrics** and user satisfaction
- **Session duration** and engagement analytics

**Analysis Features:**
- **Turn-by-turn breakdown** of conversation flow
- **Token usage per entry** and conversation totals
- **Tool invocations** and their success rates
- **User intent analysis** and topic tracking
- **Conversation completion rates** and drop-off points

### Agents

Monitor autonomous agent operations and decision-making:

**Agent Monitoring:**
- **Complete iteration history** with reasoning steps
- **Tool usage patterns** and success rates
- **Decision tree visualization** and logic flow
- **Performance metrics** (iterations to completion)
- **Resource utilization** and cost analysis

**Agent Debugging:**
- **Step-by-step reasoning** logs
- **Tool call details** and results
- **Error handling** and recovery attempts
- **System prompt effectiveness** analysis
- **Completion success rates** by agent type

```ruby
# Example: Agent iteration analysis
class AdminAgentAnalyzer
  def self.analyze_agent_performance(agent)
    {
      total_iterations: agent.agent_iterations.count,
      successful_completions: agent.agent_iterations.where(success: true).count,
      average_tools_per_iteration: agent.model_tool_invocations.count / agent.agent_iterations.count.to_f,
      most_used_tools: agent.model_tool_invocations.group(:tool_class_name).count,
      average_completion_time: calculate_average_completion_time(agent)
    }
  end
end
```

### Model Tool Invocations

Track all tool usage across your AI systems:

**Tool Analytics:**
- **Usage frequency** by tool type
- **Success/failure rates** for each tool
- **Response times** and performance metrics
- **Error patterns** and common failures
- **Cost analysis** for expensive tool operations

**Tool Performance:**
- **Execution time** distribution
- **Result quality** and usefulness metrics
- **Error rate trends** over time
- **Popular tool combinations** in agent workflows
- **Resource usage** and optimization opportunities

### Statistics Dashboard

High-level analytics and reporting:

**Usage Analytics:**
- **Daily/weekly/monthly** AI interaction volumes
- **Cost tracking** by provider and model
- **Performance trends** and response time analysis
- **User engagement** and feature adoption
- **Error rate monitoring** and alerting

**Business Metrics:**
- **Cost per interaction** and ROI analysis
- **User satisfaction** scores and feedback
- **Feature utilization** rates
- **System reliability** and uptime metrics
- **Capacity planning** and scaling insights

---

## Advanced Admin Features

### Real-Time Monitoring

Monitor AI operations as they happen:

```ruby
# Example: Real-time admin dashboard with ActionCable
class AdminDashboardChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.admin?
    
    stream_from "admin_dashboard"
  end
  
  def receive_stats
    # Broadcast live statistics
    ActionCable.server.broadcast("admin_dashboard", {
      type: "stats_update",
      data: generate_real_time_stats
    })
  end
  
  private
  
  def generate_real_time_stats
    {
      active_conversations: Raif::Conversation.where("updated_at > ?", 1.hour.ago).count,
      processing_tasks: Raif::Task.where(status: :processing).count,
      recent_completions: Raif::ModelCompletion.where("created_at > ?", 5.minutes.ago).count,
      error_rate: calculate_recent_error_rate
    }
  end
end
```

### Custom Analytics

Create custom reports and analytics:

```ruby
# Example: Custom analytics for business metrics
class RaifAnalytics
  def self.generate_monthly_report(month, year)
    start_date = Date.new(year, month, 1)
    end_date = start_date.end_of_month
    
    completions = Raif::ModelCompletion.where(created_at: start_date..end_date)
    
    {
      total_interactions: completions.count,
      total_cost: completions.sum(:cost),
      average_response_time: completions.average(:response_time_ms),
      top_models: completions.group(:model_key).count.sort_by(&:last).reverse.first(5),
      error_rate: completions.where.not(error_message: nil).count / completions.count.to_f,
      daily_breakdown: generate_daily_breakdown(completions)
    }
  end
  
  def self.generate_daily_breakdown(completions)
    completions.group_by_day(:created_at).group(:model_key).count
  end
end
```

### Performance Monitoring

Track system performance and optimize operations:

```ruby
# Example: Performance monitoring middleware
class RaifPerformanceMonitor
  def self.track_completion_performance(model_completion)
    metrics = {
      response_time: model_completion.response_time_ms,
      token_usage: model_completion.input_tokens + model_completion.output_tokens,
      cost: model_completion.cost,
      model_provider: model_completion.llm_provider,
      success: model_completion.error_message.nil?
    }
    
    # Send to monitoring service
    MonitoringService.track_event('raif.model_completion', metrics)
    
    # Check for performance anomalies
    check_performance_anomalies(metrics)
  end
  
  def self.check_performance_anomalies(metrics)
    if metrics[:response_time] > 30_000 # 30 seconds
      AdminMailer.performance_alert(
        "Slow response time: #{metrics[:response_time]}ms",
        metrics
      ).deliver_now
    end
    
    if metrics[:cost] > 1.0 # $1+ per completion
      AdminMailer.cost_alert(
        "High cost completion: $#{metrics[:cost]}",
        metrics
      ).deliver_now
    end
  end
end
```

---

## Customizing the Admin Interface

### Adding Custom Admin Pages

Extend the admin interface with your own pages:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Raif::Engine => '/raif'
  
  # Add custom admin routes
  namespace :raif do
    namespace :admin do
      resources :custom_analytics, only: [:index, :show]
      resources :cost_reports, only: [:index, :show]
      get 'performance_dashboard', to: 'performance#dashboard'
    end
  end
end

# app/controllers/raif/admin/custom_analytics_controller.rb
class Raif::Admin::CustomAnalyticsController < Raif::Admin::BaseController
  def index
    @analytics_data = CustomAnalyticsService.generate_overview
    @date_range = params[:date_range] || '30_days'
  end
  
  def show
    @detailed_analysis = CustomAnalyticsService.generate_detailed_report(params[:id])
  end
end
```

### Custom Admin Views

Override or extend existing admin views:

```bash
# Copy views to customize them
rails generate raif:views admin
```

```erb
<!-- app/views/raif/admin/model_completions/show.html.erb -->
<div class="admin-completion-detail">
  <div class="header-section">
    <h1>Model Completion #<%= @model_completion.id %></h1>
    <div class="status-badges">
      <%= render 'status_badge', completion: @model_completion %>
      <%= render 'cost_badge', completion: @model_completion %>
    </div>
  </div>
  
  <div class="metrics-grid">
    <%= render 'performance_metrics', completion: @model_completion %>
    <%= render 'token_usage', completion: @model_completion %>
    <%= render 'timing_analysis', completion: @model_completion %>
  </div>
  
  <div class="content-sections">
    <%= render 'request_details', completion: @model_completion %>
    <%= render 'response_details', completion: @model_completion %>
    
    <% if @model_completion.error_message.present? %>
      <%= render 'error_details', completion: @model_completion %>
    <% end %>
  </div>
</div>
```

### Admin API Endpoints

Create API endpoints for admin data:

```ruby
# app/controllers/raif/admin/api/analytics_controller.rb
class Raif::Admin::Api::AnalyticsController < Raif::Admin::BaseController
  before_action :ensure_json_request
  
  def completions_over_time
    data = Raif::ModelCompletion
      .where(created_at: time_range)
      .group_by_day(:created_at)
      .count
    
    render json: { data: data, period: params[:period] }
  end
  
  def cost_breakdown
    data = Raif::ModelCompletion
      .where(created_at: time_range)
      .group(:llm_provider)
      .sum(:cost)
    
    render json: { data: data, total_cost: data.values.sum }
  end
  
  def top_performing_models
    data = Raif::ModelCompletion
      .where(created_at: time_range)
      .where(error_message: nil)
      .group(:model_key)
      .average(:response_time_ms)
      .sort_by(&:last)
      .first(10)
    
    render json: { data: data }
  end
  
  private
  
  def time_range
    case params[:period]
    when '7d'
      7.days.ago..Time.current
    when '30d'
      30.days.ago..Time.current
    when '90d'
      90.days.ago..Time.current
    else
      30.days.ago..Time.current
    end
  end
  
  def ensure_json_request
    request.format = :json
  end
end
```

---

## Admin Best Practices

### Data Retention and Privacy

<div class="callout callout-warning">
<div class="callout-title">⚠️ Data Management</div>
<ul>
<li><strong>Regular cleanup</strong>: Implement retention policies for old completion data</li>
<li><strong>Sensitive data</strong>: Consider masking or removing PII from admin views</li>
<li><strong>Access logs</strong>: Track who accesses what data in the admin interface</li>
<li><strong>Export controls</strong>: Limit data export capabilities to authorized users</li>
</ul>
</div>

### Performance Optimization

```ruby
# Example: Efficient admin queries with pagination
class RaifAdminOptimizer
  def self.efficient_completions_query(page: 1, per_page: 50, filters: {})
    query = Raif::ModelCompletion.includes(:task, :conversation, :agent)
    
    # Apply filters efficiently
    query = query.where(llm_provider: filters[:provider]) if filters[:provider]
    query = query.where('created_at >= ?', filters[:start_date]) if filters[:start_date]
    query = query.where('cost >= ?', filters[:min_cost]) if filters[:min_cost]
    
    # Use cursor pagination for better performance
    query = query.order(:id).limit(per_page)
    query = query.where('id > ?', filters[:after_id]) if filters[:after_id]
    
    query
  end
end
```

### Monitoring and Alerting

Set up automated monitoring for admin health:

```ruby
# Example: Admin health monitoring
class AdminHealthMonitor
  def self.check_system_health
    checks = {
      database_connectivity: check_database,
      recent_activity: check_recent_activity,
      error_rates: check_error_rates,
      response_times: check_response_times,
      cost_anomalies: check_cost_anomalies
    }
    
    failing_checks = checks.select { |_, status| status[:status] == :failing }
    
    if failing_checks.any?
      AdminMailer.health_check_failures(failing_checks).deliver_now
    end
    
    checks
  end
  
  def self.check_recent_activity
    recent_count = Raif::ModelCompletion.where('created_at > ?', 1.hour.ago).count
    
    if recent_count == 0
      { status: :warning, message: "No AI activity in the last hour" }
    else
      { status: :healthy, message: "#{recent_count} completions in the last hour" }
    end
  end
  
  def self.check_error_rates
    total = Raif::ModelCompletion.where('created_at > ?', 1.hour.ago).count
    errors = Raif::ModelCompletion.where('created_at > ? AND error_message IS NOT NULL', 1.hour.ago).count
    
    error_rate = total > 0 ? (errors.to_f / total) : 0
    
    if error_rate > 0.1 # 10% error rate threshold
      { status: :failing, message: "High error rate: #{(error_rate * 100).round(1)}%" }
    else
      { status: :healthy, message: "Error rate: #{(error_rate * 100).round(1)}%" }
    end
  end
end
```

### Security Considerations

```ruby
# Example: Admin activity logging
class AdminActivityLogger
  def self.log_admin_action(user, action, resource, details = {})
    AdminActivityLog.create!(
      user: user,
      action: action,
      resource_type: resource.class.name,
      resource_id: resource.id,
      details: details,
      ip_address: current_ip_address,
      user_agent: current_user_agent,
      created_at: Time.current
    )
  end
  
  # Usage in admin controllers
  def show
    @model_completion = Raif::ModelCompletion.find(params[:id])
    AdminActivityLogger.log_admin_action(
      current_user, 
      'view', 
      @model_completion,
      { viewed_sensitive_data: @model_completion.contains_sensitive_data? }
    )
  end
end
```

The Web Admin interface provides powerful visibility into your AI operations, enabling you to monitor performance, debug issues, and optimize your AI-powered features effectively! 