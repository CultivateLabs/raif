---
layout: default
title: Testing
nav_order: 7
description: "Testing with Raif helpers and factories"
---

# Testing

Raif includes RSpec helpers and FactoryBot factories to help with testing in your application.

To use the helpers, add the following to your `rails_helper.rb`:

```ruby
require "raif/rspec"

RSpec.configure do |config|
  config.include Raif::RspecHelpers
end
```

You can then use the helpers to stub LLM calls:

```ruby
it "stubs a document summarization task" do
  # the messages argument is the array of messages sent to the LLM. It will look something like:
  # [{"role" => "user", "content" => "The prompt from the Raif::Tasks::DocumentSummarization task" }]
  # The model_completion argument is the Raif::ModelCompletion record that was created for this task.
  stub_raif_task(Raif::Tasks::DocumentSummarization) do |messages, model_completion|
    "Stub out the response from the LLM"
  end

  user = FactoryBot.create(:user) # assumes you have a User model & factory
  document = FactoryBot.create(:document) # assumes you have a Document model & factory
  task = Raif::Tasks::DocumentSummarization.run(document: document, creator: user)

  expect(task.raw_response).to eq("Stub out the response from the LLM")
end

it "stubs a conversation" do
  user = FactoryBot.create(:user) # assumes you have a User model & factory
  conversation = FactoryBot.create(:raif_test_conversation, creator: user)
  conversation_entry = FactoryBot.create(:raif_conversation_entry, raif_conversation: conversation, creator: user)

  stub_raif_conversation(conversation) do |messages, model_completion|
    "Hello"
  end

  conversation_entry.process_entry!
  expect(conversation_entry.reload).to be_completed
  expect(conversation_entry.model_response_message).to eq("Hello")
end

it "stubs an agent" do
  i = 0
  stub_raif_agent(agent) do |messages, model_completion|
    i += 1
    if i == 1
      "<thought>I need to search.</thought>\n<action>{\"tool\": \"wikipedia_search\", \"arguments\": {\"query\": \"capital of France\"}}</action>"
    else
      "<thought>Now I know.</thought>\n<answer>Paris</answer>"
    end
  end
end
```

Raif also provides FactoryBot factories for its models. You can use them to create Raif models for testing. If you're using `factory_bot_rails`, they will be added automatically to `config.factory_bot.definition_file_paths`. The available factories can be found [here](https://github.com/CultivateLabs/raif/tree/main/spec/factories/shared).

---

**Read next:** [Demo App](demo_app)