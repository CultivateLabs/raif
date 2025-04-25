## Unreleased

- Added ability to generate embeddings. [#77](https://github.com/CultivateLabs/raif/pull/77)
- Added support for OpenRouter models. [#93](https://github.com/CultivateLabs/raif/pull/93)
- Added a Stats section to the admin interface. [#90](https://github.com/CultivateLabs/raif/pull/90)
- Each model provider's models will be enabled by default if their API key environment variable is present (e.g. OpenAI models will be enabled by default if `ENV["OPENAI_API_KEY"].present?`).
- Added `gpt-4.1`, `gpt-4.1-mini`, and `gpt-4.1-nano` models to the default list of supported LLMs. [#74](https://github.com/CultivateLabs/raif/pull/74)
- If a `creator` association implements `raif_display_name`, it will be used in the admin interface. [#65](https://github.com/CultivateLabs/raif/pull/65)
- Agent types can now implement `populate_default_model_tools` to add default model tools to the agent. `Raif::Agents::ReActAgent` will provide these via system prompt. [#66](https://github.com/CultivateLabs/raif/pull/66)
- `Raif::ModelTools::AgentFinalAnswer` removed from the default list of model tools for `Raif::Agents::ReActAgent` since answers are provided via `<answer>` tags. [#66](https://github.com/CultivateLabs/raif/pull/66)
- Estimated cost is now displayed in the admin interface for model completions. [#69](https://github.com/CultivateLabs/raif/pull/69)
- `Raif::Conversation` can now be initialized with a `response_format` to specify the format of the response. If you use something other than basic text, you should include instructions in the conversation's system prompt. [#84](https://github.com/CultivateLabs/raif/pull/84)
- `Raif::Conversation` subtypes can now implement `process_model_response_message` to do custom processing of the model response message before it is saved to the database. [#89](https://github.com/CultivateLabs/raif/pull/89)
- `Raif::ModelTool` subclasses can now override `def self.triggers_observation_to_model?` to specify if the tool call's results should be automatically provided back to the model (e.g. a SearchTool might automatically provide the observation back to the model during a `Raif::Conversation`). [#85](https://github.com/CultivateLabs/raif/pull/85)