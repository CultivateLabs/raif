## v1.2.0 (Unreleased)

- Added support for OpenAI's Responses API. [#127](https://github.com/CultivateLabs/raif/pull/127)
- Added provider-managed tools system for utilizing tools built into LLM providers:
  - `Raif::ModelTools::ProviderManaged::WebSearch`: Real-time web search
  - `Raif::ModelTools::ProviderManaged::CodeExecution`: Secure code execution
  - `Raif::ModelTools::ProviderManaged::ImageGeneration`: AI image generation
  [#127](https://github.com/CultivateLabs/raif/pull/127)
- Added `response_id` and `response_array` columns to `raif_model_completions` table for enhanced response tracking and provider-managed tools support. [#127](https://github.com/CultivateLabs/raif/pull/127)
- Added a migration checker to warn if the host app is missing any of Raif's migrations. [#129](https://github.com/CultivateLabs/raif/pull/129)
- The AWS Bedrock adapter has been renamed to be more generalized. Added support for Amazon Nova models. [#137](https://github.com/CultivateLabs/raif/pull/137)


## v1.1.0

- Added support for images and files/PDF's. [#106](https://github.com/CultivateLabs/raif/pull/106)
- Added ability to generate embeddings. [#77](https://github.com/CultivateLabs/raif/pull/77)
- Added support for OpenRouter models. [#93](https://github.com/CultivateLabs/raif/pull/93)
- Added a Stats section to the admin interface. [#90](https://github.com/CultivateLabs/raif/pull/90)
- Each model provider's models will be enabled by default if their API key environment variable is present (e.g. OpenAI models will be enabled by default if `ENV["OPENAI_API_KEY"].present?`).
- AWS Bedrock is now disabled by default. This ensures the `aws-sdk-bedrockruntime` gem is not required unless you use AWS Bedrock models. [#94](https://github.com/CultivateLabs/raif/pull/94)
- Added `gpt-4.1`, `gpt-4.1-mini`, and `gpt-4.1-nano` models to the default list of supported LLMs. [#74](https://github.com/CultivateLabs/raif/pull/74)
- Added `claude-4-sonnet` and `claude-4-opus` models to the default list of supported LLMs. [#119](https://github.com/CultivateLabs/raif/pull/119)
- `Raif::ModelTool` subclasses can now define the tool's arguments schema via a `tool_arguments_schema` block. [#96](https://github.com/CultivateLabs/raif/pull/96)
- `Raif::ModelTool` subclasses can now define `tool_description` and `example_model_invocation` via blocks. [#99](https://github.com/CultivateLabs/raif/pull/99)
- `Raif::Task` subclasses can now define a `json_response_schema` block to specify the JSON response schema for the task. [#109](https://github.com/CultivateLabs/raif/pull/109)
- If a `creator` association implements `raif_display_name`, it will be used in the admin interface. [#65](https://github.com/CultivateLabs/raif/pull/65)
- Agent types can now implement `populate_default_model_tools` to add default model tools to the agent. `Raif::Agents::ReActAgent` will provide these via system prompt. [#66](https://github.com/CultivateLabs/raif/pull/66)
- `Raif::ModelTools::AgentFinalAnswer` removed from the default list of model tools for `Raif::Agents::ReActAgent` since answers are provided via `<answer>` tags. [#66](https://github.com/CultivateLabs/raif/pull/66)
- Estimated cost is now displayed in the admin interface for model completions. [#69](https://github.com/CultivateLabs/raif/pull/69)
- `Raif::Conversation` can now be initialized with a `response_format` to specify the format of the response. If you use something other than basic text, you should include instructions in the conversation's system prompt. [#84](https://github.com/CultivateLabs/raif/pull/84)
- `Raif::Conversation` subtypes can now implement `process_model_response_message` to do custom processing of the model response message before it is saved to the database. [#89](https://github.com/CultivateLabs/raif/pull/89)
- `Raif::ModelTool` subclasses can now override `def self.triggers_observation_to_model?` to specify if the tool call's results should be automatically provided back to the model (e.g. a SearchTool might automatically provide the observation back to the model during a `Raif::Conversation`). [#85](https://github.com/CultivateLabs/raif/pull/85)
- `Raif::Task` subclasses can now set a `temperature` for the LLM via `llm_temperature`. [#95](https://github.com/CultivateLabs/raif/pull/95)
- `Raif::Task` subclasses can now set allowed tags and attributes for HTML LLM responses via `llm_response_allowed_tags` and `llm_response_allowed_attributes`. [#103](https://github.com/CultivateLabs/raif/pull/103)
- LLM API requests will now be retried if they fail. This can be configured via `llm_request_max_retries` and `llm_request_retriable_exceptions`. [#112](https://github.com/CultivateLabs/raif/pull/112)
- `Raif.config.task_system_prompt_intro` and `Raif.config.conversation_system_prompt_intro` can now be a lambda that returns a dynamic system prompt. [#116](https://github.com/CultivateLabs/raif/pull/116)
- `ApiError` classes for each model provider have been removed. Instead, API calls will raise Faraday errors. [#117](https://github.com/CultivateLabs/raif/pull/117)