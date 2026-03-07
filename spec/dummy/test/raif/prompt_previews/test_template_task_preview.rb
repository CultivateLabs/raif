# frozen_string_literal: true

class TestTemplateTaskPreview < Raif::PromptPreview
  def default
    Raif::TestTemplateTask.new(topic: "pirates")
  end

  def custom_topic
    Raif::TestTemplateTask.new(topic: "robots")
  end
end
