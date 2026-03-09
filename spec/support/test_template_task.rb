# frozen_string_literal: true

class Raif::TestTemplateTask < Raif::Task
  run_with :topic

  after_initialize -> { self.topic ||= "pirates" }

  def topic_description
    "the topic of #{topic}"
  end
end

class Raif::TestTemplateSystemPromptTask < Raif::Task
  run_with :persona

  after_initialize -> { self.persona ||= "comedian" }

  def build_prompt
    "Tell me a joke"
  end
end

class Raif::TestTemplateConversation < Raif::Conversation
  attr_writer :persona

  def persona
    @persona || "helpful assistant"
  end
end

class Raif::TestTemplateWithPartialTask < Raif::Task
  run_with :topic

  after_initialize -> { self.topic ||= "dogs" }
end

class Raif::TestTemplateAgent < Raif::Agent
  run_with :agent_role

  after_initialize -> { self.agent_role ||= "researcher" }
end
