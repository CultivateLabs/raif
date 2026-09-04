# frozen_string_literal: true

provider :open_ai do |p|
  p.references(
    models_doc: "https://platform.openai.com/docs/models",
    pricing: "https://platform.openai.com/docs/pricing",
    deprecations: "https://platform.openai.com/docs/deprecations"
  )

  p.model(
    key_base: :gpt_5_6_sol,
    api_name: "gpt-5.6-sol",
    display_name: "OpenAI GPT-5.6 Sol",
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
    key_base: :gpt_5_nano,
    api_name: "gpt-5-nano",
    display_name: "OpenAI GPT-5 Nano",
    pricing: { input_per_million: 0.05, output_per_million: 0.4 },
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
      status: :active
    },
    endpoints: {
      completions: {
        capabilities: {
          temperature: true,
          structured_outputs: false,
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
          structured_outputs: false,
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
    key_base: :o1,
    api_name: "o1",
    display_name: "OpenAI o1",
    pricing: { input_per_million: 15.0, output_per_million: 60.0 },
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
    key_base: :o3,
    api_name: "o3",
    display_name: "OpenAI o3",
    pricing: { input_per_million: 2.0, output_per_million: 8.0 },
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
    key_base: :o3_mini,
    api_name: "o3-mini",
    display_name: "OpenAI o3 Mini",
    pricing: { input_per_million: 1.1, output_per_million: 4.4 },
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
    key_base: :o4_mini,
    api_name: "o4-mini",
    display_name: "OpenAI o4 Mini",
    pricing: { input_per_million: 1.1, output_per_million: 4.4 },
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
    key_base: :o1_pro,
    api_name: "o1-pro",
    display_name: "OpenAI o1 Pro",
    pricing: { input_per_million: 150.0, output_per_million: 600.0 },
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
    key_base: :o3_pro,
    api_name: "o3-pro",
    display_name: "OpenAI o3 Pro",
    pricing: { input_per_million: 20.0, output_per_million: 80.0 },
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
    key_base: :gpt_5_pro,
    api_name: "gpt-5-pro",
    display_name: "OpenAI GPT-5 Pro",
    pricing: { input_per_million: 15.0, output_per_million: 120.0 },
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
