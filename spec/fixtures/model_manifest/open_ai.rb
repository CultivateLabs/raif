# frozen_string_literal: true

provider :open_ai do |p|
  p.references(
    models_doc: "https://platform.openai.com/docs/models",
    pricing: "https://platform.openai.com/pricing",
    deprecations: "https://platform.openai.com/docs/deprecations"
  )

  p.model(
    key_base: :gpt_test,
    api_name: "gpt-test-1",
    display_name: "OpenAI GPT Test",
    pricing: { input_per_million: 1.25, output_per_million: 10.0 },
    lifecycle: {
      status: :active,
      added_on: Date.new(2025, 8, 7)
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: false,
          provider_managed_tools: []
        }
      },
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: %i[web_search code_execution image_generation]
        }
      }
    }
  )

  p.model(
    key_base: :gpt_test_pro,
    api_name: "gpt-test-pro",
    display_name: "OpenAI GPT Test Pro",
    pricing: { input_per_million: 15.0, output_per_million: 120.0 },
    lifecycle: {
      status: :active,
      added_on: Date.new(2025, 10, 6)
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: false,
          images: true,
          pdfs: true,
          provider_managed_tools: %i[web_search]
        }
      }
    }
  )

  p.model(
    key_base: :gpt_gone,
    api_name: "gpt-gone",
    display_name: "OpenAI GPT Gone",
    pricing: { input_per_million: 1.0, output_per_million: 2.0 },
    lifecycle: {
      status: :retired,
      added_on: Date.new(2023, 1, 1),
      deprecated_on: Date.new(2025, 1, 1),
      retirement_date: Date.new(2025, 6, 1),
      replacement_key: :gpt_test
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: true,
          structured_outputs: false,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: false,
          pdfs: false,
          provider_managed_tools: []
        }
      }
    }
  )
end
