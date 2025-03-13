# frozen_string_literal: true

module Raif
  module RspecHelpers

    def stub_raif_task(task_class, &block)
      test_llm = Raif::Llm.new(
        key: :raif_test_adapter,
        api_name: "raif_test_adapter",
        api_adapter: Raif::ApiAdapters::Test
      )

      test_llm.api_adapter.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
      allow_any_instance_of(task_class).to receive(:llm){ test_llm }
    end

    def stub_raif_conversation(conversation, &block)
      test_llm = Raif::Llm.new(
        key: :raif_test_adapter,
        api_name: "raif_test_adapter",
        api_adapter: Raif::ApiAdapters::Test
      )

      test_llm.api_adapter.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if conversation.is_a?(Raif::Conversation)
        allow(conversation).to receive(:llm){ test_llm }
      else
        allow_any_instance_of(conversation).to receive(:llm){ test_llm }
      end
    end

    def stub_raif_llm(llm, &block)
      llm.api_adapter.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      test_llm
    end

  end
end
