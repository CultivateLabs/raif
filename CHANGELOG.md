## v1.5.0-pre

- Add runtime durations to admin pages [#357](https://github.com/CultivateLabs/raif/pull/357)
- Add support for DeepSeek R1 and v3.2 models via AWS Bedrock. [#358](https://github.com/CultivateLabs/raif/pull/358)
- Fix conversation tool continuations to send `observation_for_invocation` back to the model, treat blank completions as failures, and normalize consecutive same-role messages for Bedrock, Anthropic, and Google.
- Added a tool-call repair loop to `Raif::ConversationEntry`. When a tool call is malformed (unknown tool name, non-hash arguments, schema mismatch, `prepare_tool_arguments` raises), Raif re-prompts the model with synthetic user-role corrective feedback up to `Raif.config.conversation_entry_max_retries` times (default: 2) before marking the entry as failed. Each attempt produces a new `Raif::ModelCompletion` attached to the same entry and is visible in the web admin.
- Added `Raif::Concerns::ToolCallValidation`, a shared validator used by both `Raif::ConversationEntry` and `Raif::Agents::NativeToolCallingAgent`.
- Added `Raif::Conversation#on_entry_finalized(entry:)` hook, called exactly once per entry after the model response has been saved, tool calls validated and invoked, and the entry transitioned to `completed`. This is the correct location for persistent side effects (DB writes, broadcasts, enqueuing jobs). Side effects must not live in `process_model_response_message`, which is invoked on every streaming chunk and every retry attempt.
- Added `Raif.config.streaming_unsupported_model_keys`. When a caller passes a block to `Raif::Llm#chat` for a model key matching the list (entries may be `String`, `Symbol`, or `Regexp`), Raif transparently falls back to the non-streaming path. Default is `[/\Abedrock_gpt_oss_/]`, since Bedrock's Converse streaming endpoint delivers corrupted `tool_use` deltas for `openai.gpt-oss-*`. Set to `[]` to disable.
- Added `bin/probe_streaming_tool_calls` and `bin/probe_bedrock_stream_transport` diagnostic scripts for investigating suspected streaming issues with a given provider+model combination.
- **Breaking Change**: `Raif::Conversation#prompt_model_for_entry_response` now accepts an `extra_messages:` keyword argument and the gem always passes it. Subclasses that override this method must accept the new kwarg (or `**kwargs`) or they will raise `ArgumentError` on upgrade. The documented extension points (`before_prompt_model_for_entry_response`, `system_prompt_intro`, `process_model_response_message`, etc.) are unaffected.
- **Behavior Change**: `Raif::ConversationEntry` can now produce multiple `Raif::ModelCompletion` records per entry (one per repair-loop attempt). The existing `has_one :raif_model_completion` association has been scoped to return the newest attempt. A new `has_many :raif_model_completions` association exposes the full history. Set `Raif.config.conversation_entry_max_retries = 0` to restore the prior one-completion-per-entry behavior.
- **Behavior Change**: Streaming callers for Bedrock gpt-oss models now transparently fall back to non-streaming (see `streaming_unsupported_model_keys` above). Users who want the previous behavior can set `Raif.config.streaming_unsupported_model_keys = []`.

## v1.4.0

- Added Google AI adapter with support for Gemini models (2.5 Flash, 2.5 Pro, 3.0 Flash, 3.0 Pro). [#319](https://github.com/CultivateLabs/raif/pull/319)
- **Breaking Change**: `Raif::Agents::ReActAgent` has been removed in favor of `Raif::Agents::NativeToolCallingAgent`, which provides better tool calling support across all LLM providers. [#304](https://github.com/CultivateLabs/raif/pull/304)
- Improved tool call handling in agents with provider-specific formatting. Tool calls and their results are now stored in a structured format in conversation history and properly formatted for each LLM provider (OpenAI, Anthropic, Bedrock, OpenRouter). [#304](https://github.com/CultivateLabs/raif/pull/304)
- Added `provider_tool_call_id` to `Raif::ModelToolInvocation` to track tool calls across different LLM providers. [#304](https://github.com/CultivateLabs/raif/pull/304)
- Added typed message classes (`Raif::Messages::UserMessage`, `Raif::Messages::AssistantMessage`, `Raif::Messages::ToolCall`, `Raif::Messages::ToolCallResult`) for structured conversation history. [#304](https://github.com/CultivateLabs/raif/pull/304)
- Agent system prompts are now rebuilt on each iteration to ensure they reflect any changes. [#304](https://github.com/CultivateLabs/raif/pull/304)
- Admin interface now displays tool calls and tool results with distinct styling in conversation history. [#304](https://github.com/CultivateLabs/raif/pull/304)
- Improvements to the web admin interface. Added display of input/output token cost estimates. Added model tool invocation stats and filtering. [#230](https://github.com/CultivateLabs/raif/pull/230)
- Added `before_prompt_model_for_entry_response` callback to `Raif::Conversation` subclasses. [#233](https://github.com/CultivateLabs/raif/pull/233)
- Added `generating_entry_response` flag to `Raif::Conversation` to track when a conversation is generating an entry response. [#241](https://github.com/CultivateLabs/raif/pull/241)
- Added support for using other OpenAI API providers (e.g. Azure) via `Raif.config.open_ai_base_url` and `Raif.config.open_ai_api_version`. [#245](https://github.com/CultivateLabs/raif/pull/245)
- Added an optional `source` association to `Raif::Task` for tracking the source of a task. [#246](https://github.com/CultivateLabs/raif/pull/246)
- Update schema depth validation to match OpenAI's docs [#260](https://github.com/CultivateLabs/raif/pull/260)
- Add Sonnet 4.5 and Opus 4.1 [#258](https://github.com/CultivateLabs/raif/pull/258)
- Add Net::ReadTimeout and Net::OpenTimeout to retriable exceptions [#262](https://github.com/CultivateLabs/raif/pull/262)
- Add support for Azure OpenAI's API key authentication header style. [#263](https://github.com/CultivateLabs/raif/pull/263)
- Add admin page for viewing current configuration. [#264](https://github.com/CultivateLabs/raif/pull/264)
- Make it so developer can define their own, custom agent final answer tool (e.g. if you want a custom schema for the response). [##266](https://github.com/CultivateLabs/raif/pull/#266)
- `task_run_arg` has been renamed to `run_with` and is now supported by `Raif::Agent`. [#269](https://github.com/CultivateLabs/raif/pull/269)
- Add display of available model tools to the admin interface. [#273](https://github.com/CultivateLabs/raif/pull/273)
- Added `llm_messages_max_length` to `Raif::Conversation` to limit the number of conversation entries sent to the LLM. Defaults to 50 entries, configurable via `Raif.config.conversation_llm_messages_max_length_default`. [#275](https://github.com/CultivateLabs/raif/pull/275)
- JSON schemas can now utilize an instance of the task or model tool as context when building the schema. [#314](https://github.com/CultivateLabs/raif/pull/314)
- Added configurable timeout settings for LLM API requests: `request_open_timeout`, `request_read_timeout`, and `request_write_timeout`. [#321](https://github.com/CultivateLabs/raif/pull/321)

## v1.3

- Adds support for evals. See [evals docs](https://docs.raif.ai/key_raif_concepts/evals) for more information. [#215](https://github.com/CultivateLabs/raif/pull/215)
- Added support for OpenAI's GPT-OSS models. [#207](https://github.com/CultivateLabs/raif/pull/207)
- Added support for OpenAI's GPT-5 models. [#212](https://github.com/CultivateLabs/raif/pull/212)
- `Raif::Task` subclasses can now use `task_run_arg` to define persisted arguments for the task. [#214](https://github.com/CultivateLabs/raif/pull/214)

## v1.2.2

- When requesting JSON from OpenRouter models & a `json_response_schema` is provided, give the model a JSON response tool that it can call. [#177](https://github.com/CultivateLabs/raif/pull/177)
- The `Raif::ModelTool` generator now creates a partial in `app/views/raif/model_tool_invocations/_<tool_name>.html.erb` to display the tool invocation in the conversation interface. [#189](https://github.com/CultivateLabs/raif/pull/189)

## v1.2.1

- Added support for Meta's Llama 4 models. [#170](https://github.com/CultivateLabs/raif/pull/170)
- Add response format to OpenRouter API requests for JSON responses. [#171](https://github.com/CultivateLabs/raif/pull/171)
- Fix inclusion of test support files in published gem. [#172](https://github.com/CultivateLabs/raif/pull/172)

## v1.2.0

- Added streaming support to improve real-time response handling. [#149](https://github.com/CultivateLabs/raif/pull/149)
- Improved JSON parsing by stripping ASCII control characters before parsing. [#153](https://github.com/CultivateLabs/raif/pull/153)
- Added support for OpenAI's Responses API. [#127](https://github.com/CultivateLabs/raif/pull/127)
- Added provider-managed tools system for utilizing tools built into LLM providers:
  - `Raif::ModelTools::ProviderManaged::WebSearch`: Real-time web search
  - `Raif::ModelTools::ProviderManaged::CodeExecution`: Secure code execution
  - `Raif::ModelTools::ProviderManaged::ImageGeneration`: AI image generation
  [#127](https://github.com/CultivateLabs/raif/pull/127)
- Added `response_id` and `response_array` columns to `raif_model_completions` table for enhanced response tracking and provider-managed tools support. [#127](https://github.com/CultivateLabs/raif/pull/127)
- Added a migration checker to warn if the host app is missing any of Raif's migrations. [#129](https://github.com/CultivateLabs/raif/pull/129)
- The AWS Bedrock adapter has been renamed to be more generalized. Added support for Amazon Nova models. [#137](https://github.com/CultivateLabs/raif/pull/137)
- Added support for OpenAI's o-series models. [#155](https://github.com/CultivateLabs/raif/pull/155)
- The `Raif::Conversation` system prompt is now re-built on each conversation entry to ensure it is not stale. [#156](https://github.com/CultivateLabs/raif/pull/156)


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
