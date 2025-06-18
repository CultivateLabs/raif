# frozen_string_literal: true

module Raif
  module RspecHelpers

    def stubbed_llm(llm_model_key, &block)
      test_llm = Raif.llm(llm_model_key.to_sym)

      allow(test_llm).to receive(:perform_model_completion!) do |model_completion|
        result = block.call(model_completion.messages, model_completion)
        model_completion.raw_response = result if result.is_a?(String)
        model_completion.completion_tokens = rand(100..2000)
        model_completion.prompt_tokens = rand(100..2000)
        model_completion.total_tokens = model_completion.completion_tokens + model_completion.prompt_tokens
        model_completion.save!

        model_completion
      end

      test_llm
    end

    def stub_raif_task(task, &block)
      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if task.is_a?(Raif::Task)
        allow(task).to receive(:llm){ stubbed_llm(task.llm_model_key, &block) }
      else
        allow_any_instance_of(task).to receive(:llm) do |task_instance|
          stubbed_llm(task_instance.llm_model_key, &block)
        end
      end
    end

    def stub_raif_conversation(conversation, &block)
      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if conversation.is_a?(Raif::Conversation)
        allow(conversation).to receive(:llm){ stubbed_llm(conversation.llm_model_key, &block) }
      else
        allow_any_instance_of(conversation).to receive(:llm) do |conversation_instance|
          stubbed_llm(conversation_instance.llm_model_key, &block)
        end
      end
    end

    def stub_raif_agent(agent, &block)
      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }

      if agent.is_a?(Raif::Agent)
        allow(agent).to receive(:llm){ stubbed_llm(agent.llm_model_key, &block) }
      else
        allow_any_instance_of(agent).to receive(:llm) do |agent_instance|
          stubbed_llm(agent_instance.llm_model_key, &block)
        end
      end
    end

    def stub_raif_llm(llm, &block)
      llm.chat_handler = block
      allow(Raif.config).to receive(:llm_api_requests_enabled){ true }
      llm
    end

  end
end
