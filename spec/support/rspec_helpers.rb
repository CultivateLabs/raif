# frozen_string_literal: true

module Raif
  module RspecHelpers

    def stub_raif_task(task, &block)
      test_llm = Raif.llm(:raif_test_llm)
      test_llm.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if task.is_a?(Raif::Task)
        allow(task).to receive(:llm){ test_llm }
      else
        allow_any_instance_of(task).to receive(:llm){ test_llm }
      end
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

    def stub_raif_agent(agent, &block)
      test_llm = Raif.llm(:raif_test_llm)
      test_llm.chat_handler = block

      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if agent.is_a?(Raif::Agent)
        allow(agent).to receive(:llm){ test_llm }
      else
        allow_any_instance_of(agent).to receive(:llm){ test_llm }
      end
    end

    def stub_raif_llm(llm, &block)
      llm.chat_handler = block
      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
      llm
    end

  end
end
