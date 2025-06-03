---
layout: default
title: Customization
nav_order: 9
description: "Customizing and extending Raif for your specific needs"
---

# Customization
{: .no_toc }

Raif is designed to be highly customizable, allowing you to tailor its behavior, appearance, and functionality to match your application's specific requirements. From custom controllers and models to system prompts and LLM providers, every aspect can be modified.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Raif provides multiple levels of customization to fit your needs:

- **Configuration-based**: Simple settings in your initializer
- **Inheritance-based**: Extend base classes with custom behavior
- **Override-based**: Replace default components entirely
- **Extension-based**: Add new functionality alongside existing features

### Customization Areas

- **Controllers**: Modify web interface behavior and routing
- **Models**: Extend data models and business logic
- **Views**: Customize the user interface and styling
- **System Prompts**: Tailor AI behavior and responses
- **LLM Models**: Add support for new providers and models
- **Authorization**: Implement custom access control
- **Configuration**: Environment-specific settings and behavior

---

## Controller Customization

### Overriding Default Controllers

Replace Raif's default controllers with your own implementations:

```ruby
# Create custom controllers that inherit from Raif's base controllers
class ConversationsController < Raif::ConversationsController
  # Add custom before_actions
  before_action :track_conversation_access, only: [:show]
  before_action :check_conversation_limits, only: [:create]
  
  # Override default behavior
  def create
    @conversation = current_user.raif_conversations.build(conversation_params)
    @conversation.metadata = extract_metadata_from_request
    
    if @conversation.save
      # Custom success handling
      track_conversation_creation(@conversation)
      redirect_to conversation_path(@conversation), notice: 'Chat started successfully!'
    else
      # Custom error handling
      flash.now[:error] = "Unable to start conversation: #{@conversation.errors.full_messages.join(', ')}"
      render :new, status: :unprocessable_entity
    end
  end
  
  def show
    super # Call parent implementation
    
    # Add custom functionality
    @suggested_questions = SuggestionService.generate_for_conversation(@conversation)
    @conversation_analytics = AnalyticsService.gather_conversation_data(@conversation)
  end
  
  private
  
  def track_conversation_access(conversation)
    ConversationAnalytics.track_access(
      conversation: conversation,
      user: current_user,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end
  
  def check_conversation_limits
    if current_user.raif_conversations.active.count >= current_user.conversation_limit
      redirect_to conversations_path, alert: 'You have reached your conversation limit.'
    end
  end
  
  def extract_metadata_from_request
    {
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      referer: request.referer,
      session_id: session.id
    }
  end
end

class ConversationEntriesController < Raif::ConversationEntriesController
  # Add real-time updates via ActionCable
  after_action :broadcast_entry_update, only: [:create]
  
  # Custom response processing
  def create
    @conversation_entry = @conversation.conversation_entries.build(conversation_entry_params)
    @conversation_entry.creator = current_user
    
    if @conversation_entry.save
      # Process in background for better UX
      ProcessConversationEntryJob.perform_later(@conversation_entry)
      
      render json: {
        status: 'processing',
        entry_id: @conversation_entry.id,
        message: 'Message received, AI is thinking...'
      }
    else
      render json: {
        status: 'error',
        errors: @conversation_entry.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  private
  
  def broadcast_entry_update
    ConversationChannel.broadcast_to(
      @conversation,
      {
        type: 'entry_created',
        entry: ConversationEntrySerializer.new(@conversation_entry).as_json
      }
    )
  end
end
```

Update your Raif configuration to use the custom controllers:

```ruby
# config/initializers/raif.rb
Raif.configure do |config|
  config.conversations_controller = "ConversationsController"
  config.conversation_entries_controller = "ConversationEntriesController"
end
```

### Adding Custom Routes

Extend Raif's routing with additional endpoints:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Raif::Engine => '/raif'
  
  # Add custom routes alongside Raif
  scope '/raif' do
    resources :conversation_templates, only: [:index, :show, :create]
    resources :conversation_analytics, only: [:index, :show]
    
    # API endpoints
    namespace :api do
      namespace :v1 do
        resources :conversations do
          member do
            post :star
            delete :unstar
            get :export
          end
          
          resources :entries, controller: 'conversation_entries' do
            member do
              post :regenerate
              patch :edit_message
            end
          end
        end
      end
    end
  end
end
```

---

## Model Customization

### Extending Model Behavior

Customize Raif models to add application-specific functionality:

```ruby
# Change the base class for all Raif models
Raif.configure do |config|
  config.model_superclass = "CustomApplicationRecord"
end

# Create a custom base class
class CustomApplicationRecord < ApplicationRecord
  self.abstract_class = true
  
  # Add common functionality for all Raif models
  include Auditable
  include SoftDeletable
  include Encryptable
  
  # Add custom scopes
  scope :recent, -> { where('created_at > ?', 1.week.ago) }
  scope :by_user, ->(user) { where(creator: user) }
end

# Extend specific Raif models
module RaifExtensions
  module Conversation
    extend ActiveSupport::Concern
    
    included do
      # Add custom associations
      has_many :conversation_participants, dependent: :destroy
      has_many :participants, through: :conversation_participants, source: :user
      has_many :conversation_ratings, dependent: :destroy
      has_one :conversation_summary, dependent: :destroy
      
      # Add custom validations
      validates :title, presence: true, length: { minimum: 3, maximum: 100 }
      validates :creator, presence: true
      
      # Add custom callbacks
      after_create :initialize_conversation_settings
      after_update :update_conversation_analytics
      
      # Add custom scopes
      scope :active, -> { where(status: 'active') }
      scope :archived, -> { where(status: 'archived') }
      scope :with_participants, -> { joins(:conversation_participants).distinct }
    end
    
    # Add custom methods
    def add_participant(user, role: 'participant')
      conversation_participants.create!(
        user: user,
        role: role,
        joined_at: Time.current
      )
    end
    
    def average_rating
      conversation_ratings.average(:rating) || 0
    end
    
    def can_be_accessed_by?(user)
      creator == user || participants.include?(user) || user.admin?
    end
    
    def generate_summary!
      summary_text = ConversationSummarizer.new(self).generate
      create_conversation_summary!(content: summary_text)
    end
    
    private
    
    def initialize_conversation_settings
      ConversationSettings.create!(
        conversation: self,
        auto_save: true,
        notifications_enabled: true,
        privacy_level: 'private'
      )
    end
    
    def update_conversation_analytics
      ConversationAnalyticsUpdater.perform_async(id) if saved_change_to_updated_at?
    end
  end
  
  module Task
    extend ActiveSupport::Concern
    
    included do
      # Add custom associations
      has_many :task_attachments, dependent: :destroy
      has_many :task_reviews, dependent: :destroy
      has_one :task_configuration, dependent: :destroy
      
      # Add custom enums
      enum priority: { low: 0, normal: 1, high: 2, urgent: 3 }
      enum complexity: { simple: 0, moderate: 1, complex: 2, expert: 3 }
      
      # Add custom validations
      validates :priority, presence: true
      validate :validate_configuration_consistency
      
      # Add custom callbacks
      before_create :assign_task_number
      after_completion :trigger_notifications
    end
    
    def estimated_cost
      TaskCostCalculator.new(self).calculate
    end
    
    def can_be_executed_by?(user)
      creator == user || user.can_execute_task?(self)
    end
    
    def requires_review?
      complexity.in?(['complex', 'expert']) || priority == 'urgent'
    end
    
    private
    
    def assign_task_number
      self.task_number = TaskNumberGenerator.next_number
    end
    
    def validate_configuration_consistency
      return unless task_configuration
      
      if complexity == 'simple' && task_configuration.max_iterations > 3
        errors.add(:complexity, "Simple tasks should not require many iterations")
      end
    end
    
    def trigger_notifications
      TaskCompletionNotificationJob.perform_later(self)
    end
  end
end

# Include the extensions
Raif::Conversation.include RaifExtensions::Conversation
Raif::Task.include RaifExtensions::Task
```

### Custom Model Associations

Add relationships between Raif models and your application models:

```ruby
# In your User model
class User < ApplicationRecord
  # Raif associations
  has_many :raif_conversations, 
           class_name: 'Raif::Conversation', 
           foreign_key: 'creator_id',
           dependent: :destroy
           
  has_many :raif_tasks, 
           class_name: 'Raif::Task', 
           foreign_key: 'creator_id',
           dependent: :destroy
           
  has_many :raif_agents, 
           class_name: 'Raif::Agent', 
           foreign_key: 'creator_id',
           dependent: :destroy
  
  # Custom associations
  has_many :conversation_participants, dependent: :destroy
  has_many :participated_conversations, 
           through: :conversation_participants, 
           source: :conversation
  
  has_one :raif_preferences, dependent: :destroy
  has_many :conversation_ratings, dependent: :destroy
  
  # Custom methods
  def raif_usage_this_month
    raif_conversations.where(created_at: Time.current.beginning_of_month..Time.current).count +
    raif_tasks.where(created_at: Time.current.beginning_of_month..Time.current).count
  end
  
  def conversation_limit
    return Float::INFINITY if admin?
    
    case subscription_tier
    when 'basic' then 10
    when 'pro' then 50
    when 'enterprise' then Float::INFINITY
    else 5
    end
  end
  
  def preferred_llm_model
    raif_preferences&.preferred_model || 'open_ai_gpt_4o'
  end
end

# Supporting models
class ConversationParticipant < ApplicationRecord
  belongs_to :conversation, class_name: 'Raif::Conversation'
  belongs_to :user
  
  validates :role, inclusion: { in: %w[participant moderator admin] }
  validates :user_id, uniqueness: { scope: :conversation_id }
end

class RaifPreferences < ApplicationRecord
  belongs_to :user
  
  validates :preferred_model, inclusion: { 
    in: Raif.llm_registry.keys.map(&:to_s) 
  }
  
  serialize :notification_settings, Hash
  serialize :ui_preferences, Hash
end

class ConversationRating < ApplicationRecord
  belongs_to :conversation, class_name: 'Raif::Conversation'
  belongs_to :user
  
  validates :rating, inclusion: { in: 1..5 }
  validates :user_id, uniqueness: { scope: :conversation_id }
end
```

---

## View Customization

### Copying and Modifying Views

Generate copies of Raif's views to customize them:

```bash
# Copy all conversation-related views
rails generate raif:views

# Copy specific view types
rails generate raif:views conversations
rails generate raif:views conversation_entries
rails generate raif:views admin
```

This copies views to your application:
- `app/views/raif/conversations/`
- `app/views/raif/conversation_entries/`
- `app/views/raif/admin/`

### Custom View Components

Create reusable view components for Raif features:

```ruby
# app/components/raif/conversation_component.rb
class Raif::ConversationComponent < ViewComponent::Base
  def initialize(conversation:, current_user:, options: {})
    @conversation = conversation
    @current_user = current_user
    @options = default_options.merge(options)
  end
  
  private
  
  attr_reader :conversation, :current_user, :options
  
  def default_options
    {
      show_participants: true,
      show_rating: true,
      show_analytics: false,
      theme: 'default'
    }
  end
  
  def conversation_class
    classes = ['conversation-container']
    classes << "conversation-#{conversation.status}"
    classes << "theme-#{options[:theme]}"
    classes.join(' ')
  end
  
  def can_rate_conversation?
    current_user && current_user != conversation.creator && !already_rated?
  end
  
  def already_rated?
    conversation.conversation_ratings.exists?(user: current_user)
  end
end
```

```erb
<!-- app/components/raif/conversation_component.html.erb -->
<div class="<%= conversation_class %>" data-conversation-id="<%= conversation.id %>">
  <div class="conversation-header">
    <h3 class="conversation-title"><%= conversation.title %></h3>
    
    <% if options[:show_participants] && conversation.participants.any? %>
      <div class="conversation-participants">
        <span class="participants-label">Participants:</span>
        <% conversation.participants.each do |participant| %>
          <span class="participant-badge"><%= participant.name %></span>
        <% end %>
      </div>
    <% end %>
    
    <div class="conversation-meta">
      <span class="conversation-date">
        Started <%= time_ago_in_words(conversation.created_at) %> ago
      </span>
      
      <% if options[:show_rating] %>
        <span class="conversation-rating">
          ⭐ <%= number_with_precision(conversation.average_rating, precision: 1) %>
        </span>
      <% end %>
    </div>
  </div>
  
  <div class="conversation-entries">
    <%= render conversation.conversation_entries.order(:created_at) %>
  </div>
  
  <% if can_rate_conversation? && options[:show_rating] %>
    <%= render 'raif/shared/rating_form', conversation: conversation %>
  <% end %>
  
  <% if options[:show_analytics] && conversation.can_be_accessed_by?(current_user) %>
    <%= render 'raif/shared/conversation_analytics', conversation: conversation %>
  <% end %>
</div>
```

### Custom Styling and Themes

Create custom themes for Raif components:

```scss
// app/assets/stylesheets/raif_custom.scss

// Custom color scheme
:root {
  --raif-primary: #your-brand-color;
  --raif-secondary: #your-secondary-color;
  --raif-accent: #your-accent-color;
  --raif-background: #your-bg-color;
  --raif-text: #your-text-color;
}

// Customize conversation styling
.conversation-container {
  border-radius: 12px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  background: var(--raif-background);
  
  &.theme-dark {
    background: #2a2a2a;
    color: #ffffff;
  }
  
  &.theme-minimal {
    box-shadow: none;
    border: 1px solid #e1e5e9;
  }
}

.conversation-entry {
  &.user-entry {
    .entry-content {
      background: var(--raif-primary);
      color: white;
      border-radius: 18px 18px 4px 18px;
    }
  }
  
  &.assistant-entry {
    .entry-content {
      background: #f8f9fa;
      border-radius: 18px 18px 18px 4px;
    }
  }
}

// Responsive design
@media (max-width: 768px) {
  .conversation-container {
    margin: 0 -1rem;
    border-radius: 0;
  }
}
```

---

## System Prompt Customization

### Global System Prompt Configuration

Customize system prompts for all conversations and tasks:

```ruby
# config/initializers/raif.rb
Raif.configure do |config|
  # Static system prompt intro
  config.conversation_system_prompt_intro = "You are a helpful AI assistant specialized in customer support for our SaaS platform."
  
  config.task_system_prompt_intro = "You are an expert data analyst who provides clear, actionable insights."
  
  # Dynamic system prompts with lambdas
  config.conversation_system_prompt_intro = ->(conversation) {
    base_intro = "You are a helpful AI assistant"
    
    case conversation.creator.user_type
    when 'admin'
      "#{base_intro} with administrative knowledge and elevated permissions."
    when 'developer'
      "#{base_intro} specialized in technical support and development assistance."
    when 'customer'
      "#{base_intro} focused on providing excellent customer service."
    else
      "#{base_intro} ready to help with any questions or tasks."
    end
  }
  
  config.task_system_prompt_intro = ->(task) {
    context = []
    
    # Add user context
    context << "User role: #{task.creator.role}"
    context << "User timezone: #{task.creator.timezone}"
    
    # Add task context
    context << "Task priority: #{task.priority}" if task.respond_to?(:priority)
    context << "Expected complexity: #{task.complexity}" if task.respond_to?(:complexity)
    
    # Add temporal context
    context << "Current date: #{Date.current.strftime('%B %d, %Y')}"
    context << "Current time: #{Time.current.in_time_zone(task.creator.timezone).strftime('%I:%M %p %Z')}"
    
    "You are an expert AI assistant. Context: #{context.join(', ')}."
  }
end
```

### Custom System Prompt Builders

Create sophisticated system prompt generation:

```ruby
# app/services/custom_system_prompt_builder.rb
class CustomSystemPromptBuilder
  def self.for_conversation(conversation)
    new(conversation).build_conversation_prompt
  end
  
  def self.for_task(task)
    new(task).build_task_prompt
  end
  
  def initialize(context)
    @context = context
  end
  
  def build_conversation_prompt
    prompt_parts = [
      base_assistant_definition,
      user_context_section,
      conversation_context_section,
      behavioral_guidelines,
      technical_constraints
    ]
    
    prompt_parts.compact.join("\n\n")
  end
  
  def build_task_prompt
    prompt_parts = [
      task_specialist_definition,
      user_context_section,
      task_context_section,
      output_format_requirements,
      quality_standards
    ]
    
    prompt_parts.compact.join("\n\n")
  end
  
  private
  
  attr_reader :context
  
  def base_assistant_definition
    case context.creator.role
    when 'technical_user'
      "You are a technical AI assistant with deep knowledge of software development, APIs, and system architecture."
    when 'business_user'
      "You are a business-focused AI assistant specializing in strategy, analytics, and process optimization."
    when 'customer_support'
      "You are a customer support specialist AI with empathy, patience, and comprehensive product knowledge."
    else
      "You are a versatile AI assistant capable of helping with a wide range of topics and tasks."
    end
  end
  
  def user_context_section
    user = context.creator
    
    context_info = [
      "User: #{user.name} (#{user.role})",
      "Experience level: #{user.experience_level}",
      "Preferred communication style: #{user.communication_style}",
      "Timezone: #{user.timezone}"
    ]
    
    if user.preferences.any?
      context_info << "User preferences: #{user.preferences.to_sentence}"
    end
    
    "USER CONTEXT:\n#{context_info.join("\n")}"
  end
  
  def conversation_context_section
    return nil unless context.is_a?(Raif::Conversation)
    
    context_info = [
      "Conversation type: #{context.conversation_type}",
      "Started: #{context.created_at.strftime('%B %d, %Y at %I:%M %p')}",
      "Current entry count: #{context.conversation_entries.count}"
    ]
    
    if context.conversation_entries.any?
      last_entry = context.conversation_entries.last
      context_info << "Last interaction: #{time_ago_in_words(last_entry.created_at)} ago"
    end
    
    "CONVERSATION CONTEXT:\n#{context_info.join("\n")}"
  end
  
  def task_context_section
    return nil unless context.is_a?(Raif::Task)
    
    context_info = [
      "Task type: #{context.class.name.demodulize}",
      "Priority: #{context.priority}",
      "Expected duration: #{context.estimated_duration}"
    ]
    
    if context.respond_to?(:requirements) && context.requirements.present?
      context_info << "Requirements: #{context.requirements}"
    end
    
    "TASK CONTEXT:\n#{context_info.join("\n")}"
  end
  
  def behavioral_guidelines
    guidelines = [
      "- Be helpful, accurate, and concise",
      "- Ask clarifying questions when needed",
      "- Provide step-by-step explanations for complex topics",
      "- Acknowledge when you don't know something"
    ]
    
    case context.creator.communication_style
    when 'formal'
      guidelines << "- Use professional, formal language"
    when 'casual'
      guidelines << "- Use friendly, conversational tone"
    when 'technical'
      guidelines << "- Use precise technical terminology"
      guidelines << "- Include relevant code examples when appropriate"
    end
    
    "BEHAVIORAL GUIDELINES:\n#{guidelines.join("\n")}"
  end
  
  def technical_constraints
    constraints = [
      "- Responses should be under 2000 words unless specifically requested otherwise",
      "- Use markdown formatting for better readability",
      "- Include relevant links or references when possible"
    ]
    
    if context.respond_to?(:response_format)
      case context.response_format
      when 'json'
        constraints << "- Respond with valid JSON format only"
      when 'html'
        constraints << "- Use proper HTML formatting with semantic elements"
      end
    end
    
    "TECHNICAL CONSTRAINTS:\n#{constraints.join("\n")}"
  end
  
  def output_format_requirements
    return nil unless context.is_a?(Raif::Task)
    
    format_requirements = case context.llm_response_format
    when :json
      "Return your response as valid JSON with the structure: { \"result\": \"your analysis\", \"confidence\": 0.95, \"sources\": [] }"
    when :html
      "Format your response using HTML with proper semantic markup. Use headings, lists, and emphasis as appropriate."
    else
      "Provide a clear, well-structured text response with proper formatting."
    end
    
    "OUTPUT FORMAT:\n#{format_requirements}"
  end
  
  def quality_standards
    standards = [
      "- Ensure accuracy and fact-check information when possible",
      "- Provide actionable insights rather than just observations",
      "- Include confidence levels for uncertain information",
      "- Cite sources when making specific claims"
    ]
    
    "QUALITY STANDARDS:\n#{standards.join("\n")}"
  end
end

# Use the custom prompt builder in your tasks/conversations
class Raif::Tasks::CustomAnalysisTask < Raif::ApplicationTask
  def build_system_prompt
    CustomSystemPromptBuilder.for_task(self)
  end
end

class Raif::Conversations::CustomSupportConversation < Raif::Conversation
  def build_system_prompt
    CustomSystemPromptBuilder.for_conversation(self)
  end
end
```

---

## Adding Custom LLM Models

### Registering New Models

Add support for new LLM models and providers:

```ruby
# config/initializers/raif.rb
Raif.configure do |config|
  # Enable existing providers
  config.open_ai_models_enabled = true
  config.anthropic_models_enabled = true
  
  # Add custom OpenRouter models
  config.open_router_models_enabled = true
  
  # Register additional models after configuration
end

# Register custom models after Raif is configured
Rails.application.config.after_initialize do
  # Register new OpenRouter models
  Raif.register_llm(Raif::Llms::OpenRouter, {
    key: :open_router_llama_3_2_90b,
    api_name: "meta-llama/llama-3.2-90b-vision-instruct",
    input_token_cost: 0.9 / 1_000_000,
    output_token_cost: 0.9 / 1_000_000,
    max_tokens: 131_072,
    supports_vision: true
  })
  
  Raif.register_llm(Raif::Llms::OpenRouter, {
    key: :open_router_qwen_32b,
    api_name: "qwen/qwen-2.5-32b-instruct",
    input_token_cost: 0.6 / 1_000_000,
    output_token_cost: 1.8 / 1_000_000,
    max_tokens: 32_768
  })
  
  # Register Ollama models for local deployment
  Raif.register_llm(Raif::Llms::Ollama, {
    key: :ollama_llama3_8b,
    api_name: "llama3:8b",
    input_token_cost: 0, # Local models are free
    output_token_cost: 0,
    base_url: ENV.fetch('OLLAMA_BASE_URL', 'http://localhost:11434')
  })
  
  # Register Google Gemini models
  Raif.register_llm(Raif::Llms::GoogleGemini, {
    key: :google_gemini_pro,
    api_name: "gemini-pro",
    input_token_cost: 0.5 / 1_000_000,
    output_token_cost: 1.5 / 1_000_000,
    supports_vision: true
  })
end
```

### Creating Custom LLM Adapters

Build adapters for new LLM providers:

```ruby
# app/models/raif/llms/custom_provider.rb
class Raif::Llms::CustomProvider < Raif::Llm
  def initialize(model_key, config)
    super
    @api_key = config[:api_key] || ENV['CUSTOM_PROVIDER_API_KEY']
    @base_url = config[:base_url] || 'https://api.customprovider.com/v1'
  end
  
  def chat(messages:, **options)
    # Prepare the request
    request_body = build_request_body(messages, options)
    response = make_api_request(request_body)
    
    # Create and return a ModelCompletion
    create_model_completion(
      raw_request: request_body,
      raw_response: response,
      response_text: extract_response_text(response),
      usage_data: extract_usage_data(response)
    )
  end
  
  private
  
  attr_reader :api_key, :base_url
  
  def build_request_body(messages, options)
    {
      model: @model_config[:api_name],
      messages: format_messages(messages),
      max_tokens: options[:max_tokens] || 4096,
      temperature: options[:temperature] || 0.7,
      stream: false
    }.compact
  end
  
  def format_messages(messages)
    messages.map do |message|
      case message
      when Hash
        # Standard message format
        message
      when String
        # Convert string to user message
        { role: 'user', content: message }
      else
        raise ArgumentError, "Unsupported message format: #{message.class}"
      end
    end
  end
  
  def make_api_request(request_body)
    uri = URI("#{base_url}/chat/completions")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{api_key}"
    request['Content-Type'] = 'application/json'
    request.body = request_body.to_json
    
    response = http.request(request)
    
    unless response.code.to_i == 200
      raise Raif::LlmError, "API request failed: #{response.code} #{response.message}"
    end
    
    JSON.parse(response.body)
  end
  
  def extract_response_text(response)
    response.dig('choices', 0, 'message', 'content') || ''
  end
  
  def extract_usage_data(response)
    usage = response['usage'] || {}
    
    {
      input_tokens: usage['prompt_tokens'] || 0,
      output_tokens: usage['completion_tokens'] || 0,
      total_tokens: usage['total_tokens'] || 0
    }
  end
end

# Register the custom provider
Rails.application.config.after_initialize do
  Raif.register_llm(Raif::Llms::CustomProvider, {
    key: :custom_provider_model_v1,
    api_name: "custom-model-v1",
    input_token_cost: 1.0 / 1_000_000,
    output_token_cost: 3.0 / 1_000_000,
    api_key: ENV['CUSTOM_PROVIDER_API_KEY'],
    base_url: ENV['CUSTOM_PROVIDER_BASE_URL']
  })
end
```

---

## Authorization and Security

### Custom Authorization Logic

Implement sophisticated authorization for Raif features:

```ruby
# app/models/raif_authorization.rb
class RaifAuthorization
  def self.conversation_access?(user, conversation)
    return false unless user&.persisted?
    
    # Owner can always access
    return true if conversation.creator == user
    
    # Participants can access
    return true if conversation.participants.include?(user)
    
    # Admins can access all conversations
    return true if user.admin?
    
    # Team members can access team conversations
    if conversation.team_id && user.team_ids.include?(conversation.team_id)
      return true
    end
    
    false
  end
  
  def self.task_execution?(user, task_class)
    return false unless user&.persisted?
    
    # Check user permissions
    permissions = user.raif_permissions || {}
    
    case task_class.name
    when /DataAnalysis/
      permissions['can_analyze_data']
    when /ContentGeneration/
      permissions['can_generate_content']
    when /AdminTask/
      user.admin?
    else
      true # Default allow for basic tasks
    end
  end
  
  def self.admin_access?(user)
    return false unless user&.persisted?
    
    user.admin? || user.raif_admin? || user.has_role?('raif_administrator')
  end
  
  def self.model_access?(user, model_key)
    return false unless user&.persisted?
    
    # Check if user has access to specific models
    case user.subscription_tier
    when 'basic'
      basic_models.include?(model_key.to_s)
    when 'pro'
      pro_models.include?(model_key.to_s)
    when 'enterprise'
      true # Access to all models
    else
      free_tier_models.include?(model_key.to_s)
    end
  end
  
  private
  
  def self.free_tier_models
    ['open_ai_gpt_3_5_turbo', 'anthropic_claude_3_5_haiku']
  end
  
  def self.basic_models
    free_tier_models + ['open_ai_gpt_4o_mini', 'anthropic_claude_3_5_sonnet']
  end
  
  def self.pro_models
    basic_models + ['open_ai_gpt_4o', 'anthropic_claude_3_opus']
  end
end

# Use in Raif configuration
Raif.configure do |config|
  config.authorize_controller_action = -> {
    RaifAuthorization.conversation_access?(current_user, @conversation)
  }
  
  config.authorize_admin_controller_action = -> {
    RaifAuthorization.admin_access?(current_user)
  }
  
  # Custom model authorization
  config.authorize_model_usage = ->(user, model_key) {
    RaifAuthorization.model_access?(user, model_key)
  }
end
```

---

## Configuration Management

### Environment-Specific Configuration

Manage different settings across environments:

```ruby
# config/initializers/raif.rb
Raif.configure do |config|
  # Base configuration
  config.open_ai_models_enabled = true
  config.anthropic_models_enabled = true
  
  # Environment-specific settings
  case Rails.env
  when 'development'
    config.default_llm_model_key = 'open_ai_gpt_3_5_turbo' # Cheaper for dev
    config.llm_request_timeout = 60 # Longer timeout for debugging
    config.enable_llm_logging = true
    config.cache_model_responses = false # Don't cache in development
    
  when 'test'
    config.default_llm_model_key = 'test_mock_model'
    config.enable_llm_logging = false
    config.auto_stub_llm_calls = true
    
  when 'staging'
    config.default_llm_model_key = 'open_ai_gpt_4o_mini'
    config.llm_request_timeout = 30
    config.enable_llm_logging = true
    config.cache_model_responses = true
    config.log_level = :info
    
  when 'production'
    config.default_llm_model_key = 'open_ai_gpt_4o'
    config.llm_request_timeout = 30
    config.enable_llm_logging = false # Don't log in production for privacy
    config.cache_model_responses = true
    config.auto_retry_failed_requests = true
    config.max_retry_attempts = 3
    config.log_level = :warn
  end
  
  # Feature flags
  config.enable_conversation_rating = ENV.fetch('ENABLE_CONVERSATION_RATING', 'true') == 'true'
  config.enable_advanced_analytics = ENV.fetch('ENABLE_ADVANCED_ANALYTICS', 'false') == 'true'
  config.enable_real_time_updates = ENV.fetch('ENABLE_REAL_TIME_UPDATES', 'true') == 'true'
  
  # Performance settings
  config.max_conversation_entries = ENV.fetch('MAX_CONVERSATION_ENTRIES', '100').to_i
  config.conversation_context_window = ENV.fetch('CONVERSATION_CONTEXT_WINDOW', '20').to_i
  config.task_timeout_seconds = ENV.fetch('TASK_TIMEOUT_SECONDS', '300').to_i
  
  # Security settings
  config.encrypt_stored_content = ENV.fetch('ENCRYPT_STORED_CONTENT', 'false') == 'true'
  config.enable_audit_logging = ENV.fetch('ENABLE_AUDIT_LOGGING', 'true') == 'true'
  config.max_file_upload_size = ENV.fetch('MAX_FILE_UPLOAD_SIZE', '50').to_i.megabytes
end
```

### Dynamic Configuration

Implement configuration that can be changed at runtime:

```ruby
# app/models/raif_setting.rb
class RaifSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value_type, inclusion: { in: %w[string integer float boolean json] }
  
  serialize :value, JSON
  
  def self.get(key, default = nil)
    setting = find_by(key: key)
    return default unless setting
    
    case setting.value_type
    when 'boolean'
      setting.value == 'true' || setting.value == true
    when 'integer'
      setting.value.to_i
    when 'float'
      setting.value.to_f
    when 'json'
      JSON.parse(setting.value) rescue default
    else
      setting.value
    end
  end
  
  def self.set(key, value, value_type = nil)
    value_type ||= detect_type(value)
    
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.value_type = value_type
    setting.save!
  end
  
  private
  
  def self.detect_type(value)
    case value
    when TrueClass, FalseClass
      'boolean'
    when Integer
      'integer'
    when Float
      'float'
    when Hash, Array
      'json'
    else
      'string'
    end
  end
end

# Use dynamic settings in Raif configuration
class DynamicRaifConfig
  def self.default_model_key
    RaifSetting.get('default_llm_model', 'open_ai_gpt_4o')
  end
  
  def self.max_conversation_length
    RaifSetting.get('max_conversation_length', 50)
  end
  
  def self.enable_feature?(feature_name)
    RaifSetting.get("enable_#{feature_name}", false)
  end
  
  def self.model_costs
    RaifSetting.get('model_costs', {})
  end
end

# Admin interface for managing settings
class Admin::RaifSettingsController < ApplicationController
  before_action :ensure_admin
  
  def index
    @settings = RaifSetting.all.order(:key)
  end
  
  def update
    setting = RaifSetting.find(params[:id])
    setting.update!(setting_params)
    
    # Trigger configuration reload if needed
    RaifConfigurationReloader.reload! if setting.key.in?(critical_settings)
    
    redirect_to admin_raif_settings_path, notice: 'Setting updated successfully'
  end
  
  private
  
  def setting_params
    params.require(:raif_setting).permit(:value, :value_type)
  end
  
  def critical_settings
    ['default_llm_model', 'enable_caching', 'max_tokens']
  end
end
```

Raif's extensive customization options allow you to tailor every aspect of the framework to match your application's unique requirements while maintaining the power and simplicity of the core AI features! 