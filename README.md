# Raif

[![Gem Version](https://badge.fury.io/rb/raif.svg)](https://badge.fury.io/rb/raif)
[![Build Status](https://github.com/cultivatelabs/raif/actions/workflows/ci.yml/badge.svg)](https://github.com/cultivate-labs/raif/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


Raif (Ruby AI Framework) is a Rails engine that helps you add AI-powered features to your Rails apps, such as tasks, conversations, and agents.  It supports for multiple LLM providers including OpenAI, Anthropic Claude, and AWS Bedrock (with more coming soon).

Raif is built by [Cultivate Labs](https://www.cultivatelabs.com) and is used to power [ARC](https://www.arcanalysis.ai), an AI-powered research & analysis platform.

# Installation

Add this line to your application's Gemfile:

```ruby
gem "raif"
```

And then execute:
```bash
bundle install
```

# Setup

1. Run the install generator:
```bash
rails generate raif:install
```

This will:
- Create a configuration file at `config/initializers/raif.rb`
- Copy Raif's database migrations to your application
- Mount Raif's engine at `/raif` in your application's `config/routes.rb` file

2. Run the migrations:
```bash
rails db:migrate
```

3. Configure authentication and authorization for Raif's controllers in `config/initializers/raif.rb`:

```ruby
Raif.configure do |config|
  # Configure who can access non-admin controllers
  # For example, to allow all logged in users:
  config.authorize_controller_action = ->{ current_user.present? }

  # Configure who can access admin controllers
  # For example, to allow users with admin privileges:
  config.authorize_admin_controller_action = ->{ current_user&.admin? }
end
```

4. Configure your LLM providers. You'll need at least one of:

## OpenAI
```ruby
Raif.configure do |config|
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.open_ai_models_enabled = true
  config.default_llm_model_key = "open_ai_gpt_4o"
end
```

Available OpenAI models:
- `open_ai_gpt_4o_mini`
- `open_ai_gpt_4o`
- `open_ai_gpt_3_5_turbo`

## Anthropic Claude
```ruby
Raif.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.anthropic_models_enabled = true
  config.default_llm_model_key = "anthropic_claude_3_5_sonnet"
end
```

Available Anthropic models:
- `anthropic_claude_3_7_sonnet`
- `anthropic_claude_3_5_sonnet`
- `anthropic_claude_3_5_haiku`
- `anthropic_claude_3_opus`

## AWS Bedrock (Claude)
```ruby
Raif.configure do |config|
  config.anthropic_bedrock_models_enabled = true
  config.aws_bedrock_region = "us-east-1" # or your preferred region
  config.default_llm_model_key = "bedrock_claude_3_5_sonnet"
end
```

Available Bedrock models:
- `bedrock_claude_3_5_sonnet`
- `bedrock_claude_3_7_sonnet`
- `bedrock_claude_3_5_haiku`
- `bedrock_claude_3_opus`

Note: Raif utilizes the [AWS Bedrock gem](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/BedrockRuntime/Client.html) and AWS credentials should be configured via the AWS SDK (environment variables, IAM role, etc.)

# Chatting with the LLM

When using Raif, it's generally recommended that you use one of the [higher level abstractions](#key-raif-concepts) in your application. But when needed, you can utilize `Raif::Llm` to chat with the model directly. All calls to the LLM will create and return a `Raif::ModelCompletion` record, providing you a log of all interactions with the LLM. 

Call `Raif::Llm#chat` with either a `message` string or `messages` array.:
```
llm = Raif.llm(:open_ai_gpt_4o)
model_completion = llm.chat(message: "Hello")
puts model_completion.raw_response
# => "Hello! How can I assist you today?"
```

The `Raif::ModelCompletion` class will handle parsing the response for you, should you ask for a different response format (which can be one of `:html`, `:text`, or `:json`). You can also provide a `system_prompt` to the `chat` method:
```
llm = Raif.llm(:open_ai_gpt_4o)
messages = [
  { role: "user", content: "Hello" },
  { role: "assistant", content: "Hello! How can I assist you today?" },
  { role: "user", content: "Can you you tell me a joke?" },
]

system_prompt = "You are a helpful assistant who specializes in telling jokes. Your response should be a properly formatted JSON object containing a single `joke` key. Do not include any other text in your response outside the JSON object."

model_completion = llm.chat(messages: messages, response_format: :json, system_prompt: system_prompt)
puts model_completion.raw_response
# => ```json
# => {
# =>   "joke": "Why don't skeletons fight each other? They don't have the guts."
# => }
# => ```

puts model_completion.parsed_response # will strip backticks, parse the JSON, and give you a Ruby hash
# => {"joke" => "Why don't skeletons fight each other? They don't have the guts."}
```

# Key Raif Concepts

## Tasks
If you have a single-shot task that you want an LLM to do in your application, you should create a `Raif::Task` subclass (a generator is available), where you'll define the prompt and response format for the task and call via `Raif::Task.run`. For example, say you have a `Document` model in your app and want to have a summarization task for the LLM:

```ruby
class Raif::Tasks::DocumentSummarization < ApplicationTask
  llm_response_format :html # options are :html, :text, :json
  
  # Any attr_accessor you define can be included as an argument when calling `run`. E.g. Raif::Tasks::DocumentSummarization.run(document: document, creator: user)
  attr_accessor :document
  
  def build_system_prompt
    "You are an assistant with expertise in summarizing detailed articles into clear and concise language."
  end

  def build_prompt
    <<~PROMPT
      Consider the following information:

      Title: #{document.title}
      Text:
      ```
      #{document.content}
      ```

      Your task is to read the provided article and associated information, and summarize the article concisely and clearly in approximately 1 paragraph. Your summary should include all of the key points, views, and arguments of the text, and should only include facts referenced in the text directly. Do not add any inferences, speculations, or analysis of your own, and do not exaggerate or overstate facts. If you quote directly from the article, include quotation marks. If the text does not appear to represent the title, please return the text "Unable to generate summary" and nothing else.
    PROMPT
  end

end
```

And then run the task (typically via a background job):
```
document = Document.first # assumes your app defines a Document model
user = User.first # assumes your app defines a User model
task = Raif::Tasks::Docs::SummaryGeneration.run(document: document, creator: user)
summary = task.parsed_response
```

## Conversations

## Agents

# Web Admin

Raif includes a web admin interface for viewing all interactions with the LLM. Assuming you have the engine mounted at `/raif`, you can access the admin interface at `/raif/admin`.

The admin interface contains sections for:
- Model Completions
- Tasks
- Conversations
- Agent Invocations
- Model Tool Invocations

ADD SCREENSHOTS HERE.


# Customization

## Controllers

You can override Raif's controllers by creating your own that inherit from Raif's base controllers:

```ruby
class ConversationsController < Raif::ConversationsController
  # Your customizations here
end

class ConversationEntriesController < Raif::ConversationEntriesController
  # Your customizations here
end
```

Then update the configuration:
```ruby
Raif.configure do |config|
  config.conversations_controller = "ConversationsController"
  config.conversation_entries_controller = "ConversationEntriesController"
end
```

## Models

By default, Raif models inherit from `ApplicationRecord`. You can change this:

```ruby
Raif.configure do |config|
  config.model_superclass = "CustomRecord"
end
```

## System Prompts

You can customize the intro portion of the system prompts for conversations and tasks:

```ruby
Raif.configure do |config|
  config.conversation_system_prompt_intro = "You are a helpful assistant who specializes in customer support."
  config.task_system_prompt_intro = "You are a helpful assistant who specializes in data analysis."
end
```

# License

The gem is available as open source under the terms of the MIT License.
