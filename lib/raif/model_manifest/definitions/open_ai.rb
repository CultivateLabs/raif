# frozen_string_literal: true

provider :open_ai do |p|
  p.references(
    models_doc: "https://platform.openai.com/docs/models",
    pricing: "https://platform.openai.com/docs/pricing",
    deprecations: "https://platform.openai.com/docs/deprecations"
  )

  p.model(
    key_base: :gpt_6_astra,
    api_name: "gpt-6-astra",
    display_name: "OpenAI GPT-6 Astra",
    max_completion_tokens: 128_000,
    pricing: {
      cache_read_per_million: 1.0,
      input_per_million: 10.0,
      output_per_million: 50.0,
      note: "Above 272K input tokens, the full request costs 20.00 input / 75.00 output per million tokens."
    },
    lifecycle: {
      status: :active,
      added_on: Date.new(2026, 9, 14)
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
    key_base: :gpt_5_6_sol,
    api_name: "gpt-5.6-sol",
    display_name: "OpenAI GPT-5.6 Sol",
    pricing: {
      input_per_million: 4.0,
      output_per_million: 20.0,
      note: "Promotional short-context rate; list rate 5.00 / 30.00, long context (272K+) bills 8.00 / 30.00.",
      valid_until: Date.new(2026, 11, 21)
    },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_6_terra,
    api_name: "gpt-5.6-terra",
    display_name: "OpenAI GPT-5.6 Terra",
    pricing: { input_per_million: 2.0, output_per_million: 12.0 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_6_luna,
    api_name: "gpt-5.6-luna",
    display_name: "OpenAI GPT-5.6 Luna",
    pricing: { input_per_million: 0.2, output_per_million: 1.2 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_5,
    api_name: "gpt-5.5",
    display_name: "OpenAI GPT-5.5",
    pricing: { input_per_million: 5.0, output_per_million: 30.0 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_4,
    api_name: "gpt-5.4",
    display_name: "OpenAI GPT-5.4",
    pricing: { input_per_million: 2.5, output_per_million: 15.0 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_2,
    api_name: "gpt-5.2",
    display_name: "OpenAI GPT-5.2",
    pricing: { input_per_million: 1.75, output_per_million: 14.0 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_3,
    api_name: "gpt-5.3",
    display_name: "OpenAI GPT-5.3",
    pricing: { input_per_million: 1.75, output_per_million: 14.0 },
    lifecycle: {
      status: :retired,
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "No general-purpose gpt-5.3 API model was published; OpenAI only offered gpt-5.3-codex and the shut-down gpt-5.3-chat-latest."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_sol },
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
    key_base: :gpt_5_1,
    api_name: "gpt-5.1",
    display_name: "OpenAI GPT-5.1",
    pricing: { input_per_million: 1.25, output_per_million: 10.0 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5,
    api_name: "gpt-5",
    display_name: "OpenAI GPT-5",
    pricing: { input_per_million: 1.25, output_per_million: 10.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 6, 11),
      retirement_date: Date.new(2026, 12, 11),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-sol."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_sol },
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
    key_base: :gpt_5_4_mini,
    api_name: "gpt-5.4-mini",
    display_name: "OpenAI GPT-5.4 Mini",
    pricing: { input_per_million: 0.75, output_per_million: 4.5 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_4_nano,
    api_name: "gpt-5.4-nano",
    display_name: "OpenAI GPT-5.4 Nano",
    pricing: { input_per_million: 0.2, output_per_million: 1.25 },
    lifecycle: {
      status: :active
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
    key_base: :gpt_5_mini,
    api_name: "gpt-5-mini",
    display_name: "OpenAI GPT-5 Mini",
    pricing: { input_per_million: 0.25, output_per_million: 2.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 6, 11),
      retirement_date: Date.new(2026, 12, 11),
      replacement_key: :open_ai_responses_gpt_5_6_terra,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-terra."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_terra },
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
    key_base: :gpt_5_nano,
    api_name: "gpt-5-nano",
    display_name: "OpenAI GPT-5 Nano",
    pricing: { input_per_million: 0.05, output_per_million: 0.4 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 6, 11),
      retirement_date: Date.new(2026, 12, 11),
      replacement_key: :open_ai_responses_gpt_5_6_luna,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-luna."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_luna },
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
    key_base: :gpt_4o_mini,
    api_name: "gpt-4o-mini",
    display_name: "OpenAI GPT-4o Mini",
    pricing: { input_per_million: 0.15, output_per_million: 0.6 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: true,
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
          temperature: true,
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
    key_base: :gpt_4o,
    api_name: "gpt-4o",
    display_name: "OpenAI GPT-4o",
    pricing: { input_per_million: 2.5, output_per_million: 10.0 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: true,
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
          temperature: true,
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
    key_base: :gpt_3_5_turbo,
    api_name: "gpt-3.5-turbo",
    display_name: "OpenAI GPT-3.5 Turbo",
    pricing: { input_per_million: 0.5, output_per_million: 1.5 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 4, 22),
      retirement_date: Date.new(2026, 10, 23),
      replacement_key: :open_ai_responses_gpt_5_6_terra,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-terra."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_terra },
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
      },
      responses: {
        capabilities: {
          temperature: true,
          structured_outputs: false,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: false,
          pdfs: true,
          provider_managed_tools: %i[web_search code_execution image_generation]
        }
      }
    }
  )

  p.model(
    key_base: :gpt_4_1,
    api_name: "gpt-4.1",
    display_name: "OpenAI GPT-4.1",
    pricing: { input_per_million: 2.0, output_per_million: 8.0 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: true,
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
          temperature: true,
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
    key_base: :gpt_4_1_mini,
    api_name: "gpt-4.1-mini",
    display_name: "OpenAI GPT-4.1 Mini",
    pricing: { input_per_million: 0.4, output_per_million: 1.6 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: true,
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
          temperature: true,
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
    key_base: :gpt_4_1_nano,
    api_name: "gpt-4.1-nano",
    display_name: "OpenAI GPT-4.1 Nano",
    pricing: { input_per_million: 0.1, output_per_million: 0.4 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 4, 22),
      retirement_date: Date.new(2026, 10, 23),
      replacement_key: :open_ai_responses_gpt_5_6_luna,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-luna."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_luna },
        capabilities: {
          temperature: true,
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
          temperature: true,
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
    key_base: :o1,
    api_name: "o1",
    display_name: "OpenAI o1",
    pricing: { input_per_million: 15.0, output_per_million: 60.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 4, 22),
      retirement_date: Date.new(2026, 10, 23),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-sol."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_sol },
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
    key_base: :o3,
    api_name: "o3",
    display_name: "OpenAI o3",
    pricing: { input_per_million: 2.0, output_per_million: 8.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 6, 11),
      retirement_date: Date.new(2026, 12, 11),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-sol."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_sol },
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
    key_base: :o3_mini,
    api_name: "o3-mini",
    display_name: "OpenAI o3 Mini",
    pricing: { input_per_million: 1.1, output_per_million: 4.4 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 4, 22),
      retirement_date: Date.new(2026, 10, 23),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-sol."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_sol },
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
    key_base: :o4_mini,
    api_name: "o4-mini",
    display_name: "OpenAI o4 Mini",
    pricing: { input_per_million: 1.1, output_per_million: 4.4 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 4, 22),
      retirement_date: Date.new(2026, 10, 23),
      replacement_key: :open_ai_responses_gpt_5_6_terra,
      migration_note: "Use the matching Chat Completions or Responses endpoint for gpt-5.6-terra."
    },
    endpoints: {
      completions: {
        lifecycle: { replacement_key: :open_ai_gpt_5_6_terra },
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
    key_base: :o1_pro,
    api_name: "o1-pro",
    display_name: "OpenAI o1 Pro",
    pricing: { input_per_million: 150.0, output_per_million: 600.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 4, 22),
      retirement_date: Date.new(2026, 10, 23),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "OpenAI suggests gpt-5.6-sol with reasoning.mode: pro, a mode raif does not expose."
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: []
        }
      }
    }
  )

  p.model(
    key_base: :o3_pro,
    api_name: "o3-pro",
    display_name: "OpenAI o3 Pro",
    pricing: { input_per_million: 20.0, output_per_million: 80.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 6, 11),
      retirement_date: Date.new(2026, 12, 11),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "Use gpt-5.6-sol on the Responses API with reasoning.mode set to pro."
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: []
        }
      }
    }
  )

  p.model(
    key_base: :gpt_5_pro,
    api_name: "gpt-5-pro",
    display_name: "OpenAI GPT-5 Pro",
    pricing: { input_per_million: 15.0, output_per_million: 120.0 },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 6, 11),
      retirement_date: Date.new(2026, 12, 11),
      replacement_key: :open_ai_responses_gpt_5_6_sol,
      migration_note: "Use gpt-5.6-sol on the Responses API with reasoning.mode set to pro."
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: []
        }
      }
    }
  )

  p.model(
    key_base: :gpt_5_2_pro,
    api_name: "gpt-5.2-pro",
    display_name: "OpenAI GPT-5.2 Pro",
    pricing: { input_per_million: 21.0, output_per_million: 168.0 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: []
        }
      }
    }
  )

  p.model(
    key_base: :gpt_5_4_pro,
    api_name: "gpt-5.4-pro",
    display_name: "OpenAI GPT-5.4 Pro",
    pricing: { input_per_million: 30.0, output_per_million: 180.0 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: false,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: []
        }
      }
    }
  )

  p.model(
    key_base: :gpt_5_5_pro,
    api_name: "gpt-5.5-pro",
    display_name: "OpenAI GPT-5.5 Pro",
    pricing: { input_per_million: 30.0, output_per_million: 180.0 },
    lifecycle: {
      status: :active
    },
    endpoints: {
      responses: {
        capabilities: {
          temperature: false,
          structured_outputs: true,
          native_tool_use: true,
          streaming: true,
          batch_inference: true,
          images: true,
          pdfs: true,
          provider_managed_tools: []
        }
      }
    }
  )
end
