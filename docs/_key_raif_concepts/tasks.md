---
layout: default
title: Tasks
nav_order: 1
description: "Single-shot AI operations for organizing LLM prompts"
---

{% include table-of-contents.md %}

# Tasks Overview
`Raif::Task` is designed for single-shot LLM operations. Each task defines a prompt, system prompt, and response format (`:html`, `:text`, or `:json`). Use the generator to create a new task, which you'll call via `Raif::Task.run`. 

For example, say you have a `Document` model in your app and want to have a summarization task for the LLM:

```bash
rails generate raif:task DocumentSummarization --response-format html
```

This will create a new task in `app/models/raif/tasks/document_summarization.rb`:

```ruby
class Raif::Tasks::DocumentSummarization < Raif::ApplicationTask
  llm_response_format :html # :html, :text, or :json
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

      If the text does not appear to represent the title, please return the text "Unable to generate summary" and nothing else.
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

# JSON Response Format Tasks

If you want the LLM to return a JSON response, use `llm_response_format :json` in your task. 

If you're using OpenAI, Raif will set the response to use [JSON mode](https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#json-mode){:target="_blank"}. If you define a JSON schema using the `json_response_schema` method, it will trigger utilization of OpenAI's [structured outputs](https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#structured-outputs){:target="_blank"} feature. If you're using Anthropic, Raif will insert a tool for Claude to use to generate a JSON response.

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

# Using Model Tools

`Raif::Task` supports the use of [model tools](../key_raif_concepts/model_tools). Any model tool that is included in the task's `available_model_tools` array will be available to the LLM when the task is run.

You can provide the tools at runtime:
```ruby
Raif::Tasks::DocumentSummarization.run(
  document: document, 
  creator: user, 
  available_model_tools: ["Raif::ModelTools::GoogleSearch"]
)
```

Or if you want all instances of a task to have the tools available by default:
```ruby
class MyTask < Raif::Task
  before_create ->{
    self.available_model_tools << "Raif::ModelTools::GoogleSearch"
  }
end
```

# Task Language Preference

Tasks support the ability to specify a language preference for the LLM response. When enabled, Raif will add a line to the system prompt that looks something like:
```
You're collaborating with teammate who speaks Spanish. Please respond in Spanish.
```

You can trigger this behavior in a couple ways:

1. If the `creator` you pass to the `run` method responds to `preferred_language_key`, Raif will use that value.

2. Pass `requested_language_key` as an argument to the `run` method:
```
task = Raif::Tasks::DocumentSummarization.run(document: document, creator: user, requested_language_key: "es")
```

The current list of valid language keys can be found [here](https://github.com/CultivateLabs/raif/blob/main/lib/raif/languages.rb).

# Overriding the LLM Model

By default, `Raif::Task`'s will use the model specified in `Raif.config.default_llm_model_key`. You can override in various places. 

By passing a different model key to the `run` method:
```
task = Raif::Tasks::DocumentSummarization.run(
  document: document,
  creator: user,
  llm_model_key: "open_ai_gpt_4_1"
)
```

Overriding in the task definition:
```ruby
class MyTask < Raif::Task
  def default_llm_model_key
    if Rails.env.production?
      :open_ai_gpt_4_1
    else
      :open_ai_gpt_4_1_mini
    end
  end
end
```
