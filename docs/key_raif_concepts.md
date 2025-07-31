---
layout: default
title: Key Raif Concepts
nav_order: 4
description: "Core concepts and abstractions in Raif"
---

# Key Raif Concepts

## Tasks
If you have a single-shot task that you want an LLM to do in your application, you should create a `Raif::Task` subclass, where you'll define the prompt and response format for the task and call via `Raif::Task.run`. For example, say you have a `Document` model in your app and want to have a summarization task for the LLM:

```bash
rails generate raif:task DocumentSummarization --response-format html
```

This will create a new task in `app/models/raif/tasks/document_summarization.rb`:

```ruby
class Raif::Tasks::DocumentSummarization < Raif::ApplicationTask
  llm_response_format :html # options are :html, :text, :json
  llm_temperature 0.8 # optional, defaults to 0.7
  llm_response_allowed_tags %w[p b i div strong] # optional, defaults to Rails::HTML5::SafeListSanitizer.allowed_tags
  llm_response_allowed_attributes %w[style] # optional, defaults to Rails::HTML5::SafeListSanitizer.allowed_attributes

  # Any attr_accessor you define can be included as an argument when calling `run`. 
  # E.g. Raif::Tasks::DocumentSummarization.run(document: document, creator: user)
  attr_accessor :document
  
  def build_system_prompt
    sp = "You are an assistant with expertise in summarizing detailed articles into clear and concise language."
    sp += system_prompt_language_preference if requested_language_key.present?
    sp
  end

  def build_prompt
    <<~PROMPT
      Consider the following information:

      Title: #{document.title}
      Text:
      ```
      #{document.content}
      ```

      Your task is to read the provided article and associated information, and summarize the article concisely and clearly in approximately 1 paragraph. Your summary should include all of the key points, views, and arguments of the text, and should only include facts referenced in the text directly. Do not add any inferences, speculations, or analysis of your own, and do not exaggerate or overstate facts. If you quote directly from the article, include quotation marks.

      Format your response using basic HTML tags.

      If the text does not appear to represent the title, please return the text "#{summarization_failure_text}" and nothing else.
    PROMPT
  end

end
```

And then run the task (typically via a background job):
```
document = Document.first # assumes your app defines a Document model
user = User.first # assumes your app defines a User model
task = Raif::Tasks::DocumentSummarization.run(document: document, creator: user)
summary = task.parsed_response
```

### JSON Response Format Tasks

If you want to use a JSON response format for your task, you can do so by setting the `llm_response_format` to `:json` in your task subclass. If you're using OpenAI, this will set the response to use [JSON mode](https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#json-mode). You can also define a JSON schema, which will then trigger utilization of OpenAI's [structured outputs](https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#structured-outputs) feature. If you're using Claude, it will create a tool for Claude to use to generate a JSON response.

```bash
rails generate raif:task WebSearchQueryGeneration --response-format json
```

This will create a new task in `app/models/raif/tasks/web_search_query_generation.rb`:

```ruby
module Raif
  module Tasks
    class WebSearchQueryGeneration < Raif::ApplicationTask
      llm_response_format :json

      attr_accessor :topic

      json_response_schema do
        array :queries do
          items type: "string"
        end
      end

      def build_prompt
        <<~PROMPT
          Generate a list of 3 search queries that I can use to find information about the following topic:
          #{topic}

          Format your response as JSON.
        PROMPT
      end
    end
  end
end

```

### Task Language Preference
You can also pass in a `requested_language_key` to the `run` method. When this is provided, Raif will add a line to the system prompt requesting that the LLM respond in the specified language:
```
task = Raif::Tasks::DocumentSummarization.run(document: document, creator: user, requested_language_key: "es")
```

Would produce a system prompt that looks like this:
```
You are an assistant with expertise in summarizing detailed articles into clear and concise language.
You're collaborating with teammate who speaks Spanish. Please respond in Spanish.
```

The current list of valid language keys can be found [here](https://github.com/CultivateLabs/raif/blob/main/lib/raif/languages.rb).

## Conversations

Raif provides `Raif::Conversation` and `Raif::ConversationEntry` models that you can use to  provide an LLM-powered chat interface. It also provides controllers and views for the conversation interface.

This feature utilizes Turbo Streams, Stimulus controllers, and ActiveJob, so your application must have those set up first. 

To use it in your application, first set up the css and javascript in your application. In the `<head>` section of your layout file:
```erb
<%= stylesheet_link_tag "raif" %>
```

In an app using import maps, add the following to your `application.js` file:
```js
import "raif"
```

In a controller serving the conversation view:
```ruby
class ExampleConversationController < ApplicationController
  def show
    @conversation = Raif::Conversation.where(creator: current_user).order(created_at: :desc).first

    if @conversation.nil?
      @conversation = Raif::Conversation.new(creator: current_user)
      @conversation.save!
    end
  end
end
```

And then in the view where you'd like to display the conversation interface:
```erb
<%= raif_conversation(@conversation) %>
```

If your app already includes Bootstrap styles, this will render a conversation interface that looks something like:

![Conversation Interface](./screenshots/conversation-interface.png)

If your app does not include Bootstrap, you can [override the views](customization#views) to update styles.

### Real-time Streaming Responses

Raif conversations have built-in support for streaming responses, where the LLM's response is displayed progressively as it's being generated. Each time a conversation entry is updated during the streaming response, Raif will call `broadcast_replace_to(conversation)` (where `conversation` is the `Raif::Conversation` associated with the conversation entry). When using the `raif_conversation` view helper, it will automatically set up the subscription for you.

### Conversation Types

If your application has a specific type of conversation that you use frequently, you can create a custom conversation type by running the generator. For example, say you are implementing a customer support chatbot in your application and want to have a custom conversation type for doing this with the LLM:
```bash
rails generate raif:conversation CustomerSupport
```

This will create a new conversation type in `app/models/raif/conversations/customer_support.rb`.

You can then customize the system prompt, initial message, and available [model tools](#model-tools) for that conversation type:

```ruby
class Raif::Conversations::CustomerSupport < Raif::Conversation
  before_create -> { 
    self.available_model_tools = [
      "Raif::ModelTools::SearchKnowledgeBase",
      "Raif::ModelTools::FileSupportTicket" 
    ]
  }

  def system_prompt_intro
    <<~PROMPT
      You are a helpful assistant who specializes in customer support. You're working with a customer who is experiencing an issue with your product.
    PROMPT
  end

  def initial_chat_message
    I18n.t("#{self.class.name.underscore.gsub("/", ".")}.initial_chat_message")
  end
end
```


## Agents

Raif also provides `Raif::Agents::ReActAgent`, which implements a ReAct-style agent loop using [tool calls](#model-tools):

```ruby
# Create a new agent
agent = Raif::Agents::ReActAgent.new(
  task: "Research the history of the Eiffel Tower",
  available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
  creator: current_user
)

# Run the agent and get the final answer
final_answer = agent.run!

# Or run the agent and monitor its progress
agent.run! do |conversation_history_entry|
  Turbo::StreamsChannel.broadcast_append_to(
    :my_agent_channel,
    target: "agent-progress",
    partial: "my_partial_displaying_agent_progress",
    locals: { agent: agent, conversation_history_entry: conversation_history_entry }
  )
end
```

On each step of the agent loop, an entry will be added to the `Raif::Agent#conversation_history` and, if you pass a block to the `run!` method, the block will be called with the `conversation_history_entry` as an argument. You can use this to monitor and display the agent's progress in real-time.

The conversation_history_entry will be a hash with "role" and "content" keys:
```ruby
{
  "role" => "assistant",
  "content" => "a message here"
}
```

### Creating Custom Agents

You can create custom agents using the generator:
```bash
rails generate raif:agent WikipediaResearchAgent
```

This will create a new agent in `app/models/raif/agents/wikipedia_research_agent.rb`:

```ruby
module Raif
  module Agents
    class WikipediaResearchAgent < Raif::Agent
      # If you want to always include a certain set of model tools with this agent type,
      # uncomment this callback to populate the available_model_tools attribute with your desired model tools.
      # before_create -> {
      #   self.available_model_tools ||= [
      #     Raif::ModelTools::WikipediaSearchTool,
      #     Raif::ModelTools::FetchUrlTool
      #   ]
      # }

      # Enter your agent's system prompt here. Alternatively, you can change your agent's superclass
      # to an existing agent types (like Raif::Agents::ReActAgent) to utilize an existing system prompt.
      def build_system_prompt
        # TODO: Implement your system prompt here
      end

      # Each iteration of the agent loop will generate a new Raif::ModelCompletion record and
      # then call this method with it as an argument.
      def process_iteration_model_completion(model_completion)
        # TODO: Implement your iteration processing here
      end
    end
  end
end

```

## Model Tools

Raif provides a `Raif::ModelTool` base class that you can use to create custom tools for your agents and conversations. [`Raif::ModelTools::WikipediaSearch`](https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/wikipedia_search.rb) and [`Raif::ModelTools::FetchUrl`](https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/fetch_url.rb) tools are included as examples.

You can create your own model tools to provide to the LLM using the generator:
```bash
rails generate raif:model_tool GoogleSearch
```

This will create a new model tool in `app/models/raif/model_tools/google_search.rb`:

```ruby
class Raif::ModelTools::GoogleSearch < Raif::ModelTool
  # For example tool implementations, see: 
  # Wikipedia Search Tool: https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/wikipedia_search.rb
  # Fetch URL Tool: https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/fetch_url.rb

  # Define the schema for the arguments that the LLM should use when invoking your tool.
  # It should be a valid JSON schema. When the model invokes your tool,
  # the arguments it provides will be validated against this schema using JSON::Validator from the json-schema gem.
  #
  # All attributes will be required and additionalProperties will be set to false.
  #
  # This schema would expect the model to invoke your tool with an arguments JSON object like:
  # { "query" : "some query here" }
  tool_arguments_schema do
    string :query, description: "The query to search for"
  end

  # An example of how the LLM should invoke your tool. This should return a hash with name and arguments keys.
  # `to_json` will be called on it and provided to the LLM as an example of how to invoke your tool.
  example_model_invocation do
    {
      "name": tool_name,
      "arguments": { "query": "example query here" }
    }
  end

  tool_description do
    "Description of your tool that will be provided to the LLM so it knows when to invoke it"
  end

  # When your tool is invoked by the LLM in a Raif::Agent loop, 
  # the results of the tool invocation are provided back to the LLM as an observation.
  # This method should return whatever you want provided to the LLM.
  # For example, if you were implementing a GoogleSearch tool, this might return a JSON
  # object containing search results for the query.
  def self.observation_for_invocation(tool_invocation)
    return "No results found" unless tool_invocation.result.present?

    JSON.pretty_generate(tool_invocation.result)
  end

  # When the LLM invokes your tool, this method will be called with a `Raif::ModelToolInvocation` record as an argument.
  # It should handle the actual execution of the tool. 
  # For example, if you are implementing a GoogleSearch tool, this method should run the actual search
  # and store the results in the tool_invocation's result JSON column.
  def self.process_invocation(tool_invocation)
    # Extract arguments from tool_invocation.tool_arguments
    # query = tool_invocation.tool_arguments["query"]
    #
    # Process the invocation and perform the desired action
    # ...
    #
    # Store the results in the tool_invocation
    # tool_invocation.update!(
    #   result: {
    #     # Your result data structure
    #   }
    # )
    #
    # Return the result
    # tool_invocation.result
  end

end
```

### Provider-Managed Tools

In addition to the ability to create your own model tools, Raif supports provider-managed tools. These are tools that are built into certain LLM providers and run on the provider's infrastructure:

- **`Raif::ModelTools::ProviderManaged::WebSearch`**: Performs real-time web searches and returns relevant results
- **`Raif::ModelTools::ProviderManaged::CodeExecution`**: Executes code in a secure sandboxed environment (e.g. Python)
- **`Raif::ModelTools::ProviderManaged::ImageGeneration`**: Generates images based on text descriptions

Current provider-managed tool support:
| Provider | WebSearch | CodeExecution | ImageGeneration |
|----------|-----------|---------------|-----------------|
| OpenAI Responses API | ✅ | ✅ | ✅ |
| OpenAI Completions API | ❌ | ❌ | ❌ |
| Anthropic Claude | ✅ | ✅ | ❌ |
| AWS Bedrock (Claude) | ❌ | ❌ | ❌ |
| OpenRouter | ❌ | ❌ | ❌ |

To use provider-managed tools, include them in the `available_model_tools` array:

```ruby
# In a conversation
conversation = Raif::Conversation.create!(
  creator: current_user,
  available_model_tools: [
    "Raif::ModelTools::ProviderManaged::WebSearch",
    "Raif::ModelTools::ProviderManaged::CodeExecution"
  ]
)

# In an agent
agent = Raif::Agents::ReActAgent.new(
  task: "Search for recent news about AI and create a summary chart",
  available_model_tools: [
    "Raif::ModelTools::ProviderManaged::WebSearch",
    "Raif::ModelTools::ProviderManaged::CodeExecution"
  ],
  creator: current_user
)

# Directly in a chat
llm = Raif.llm(:open_ai_responses_gpt_4_1)
model_completion = llm.chat(
  messages: [{ role: "user", content: "What are the latest developments in Ruby on Rails?" }], 
  available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch]
)
```

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