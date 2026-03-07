# frozen_string_literal: true

class TestTemplateSystemPromptTaskPreview < Raif::PromptPreview
  def default
    Raif::TestTemplateSystemPromptTask.new(persona: "comedian")
  end
end
