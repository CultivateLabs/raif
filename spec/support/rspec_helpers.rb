# frozen_string_literal: true

module Raif
  module RspecHelpers

    def stub_raif_task(task_class, &block)
      test_llm = Raif.llm(:raif_test_llm)
      test_llm.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
      allow_any_instance_of(task_class).to receive(:llm){ test_llm }
    end

    def stub_raif_conversation(conversation, &block)
      test_llm = Raif.llm(:raif_test_llm)
      test_llm.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if conversation.is_a?(Raif::Conversation)
        allow(conversation).to receive(:llm){ test_llm }
      else
        allow_any_instance_of(conversation).to receive(:llm){ test_llm }
      end
    end

    def stub_raif_agent_invocation(agent_invocation, &block)
      test_llm = Raif.llm(:raif_test_llm)
      test_llm.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if agent_invocation.is_a?(Raif::AgentInvocation)
        allow(agent_invocation).to receive(:llm){ test_llm }
      else
        allow_any_instance_of(agent_invocation).to receive(:llm){ test_llm }
      end
    end

    def stub_raif_llm(llm, &block)
      llm.chat_handler = block
      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
      llm
    end

  end
end
