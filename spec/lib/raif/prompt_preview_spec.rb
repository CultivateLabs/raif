# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::PromptPreview do
  before(:all) do
    # Ensure previews are loaded
    Raif::PromptPreview.all
  end

  let(:task_preview) { Raif::PromptPreview.all.find { |k| k.name == "TestTemplateTaskPreview" } }
  let(:system_prompt_preview) { Raif::PromptPreview.all.find { |k| k.name == "TestTemplateSystemPromptTaskPreview" } }

  describe ".all" do
    it "returns all preview classes" do
      preview_names = described_class.all.map(&:name)
      expect(preview_names).to include("TestTemplateTaskPreview")
      expect(preview_names).to include("TestTemplateSystemPromptTaskPreview")
    end
  end

  describe ".preview_methods" do
    it "returns public instance methods for the preview class" do
      expect(task_preview.preview_methods).to eq([:custom_topic, :default])
    end

    it "returns preview methods for system prompt preview" do
      expect(system_prompt_preview.preview_methods).to eq([:default])
    end
  end

  describe ".render_preview" do
    it "renders the prompt from a template" do
      result = task_preview.render_preview(:default)
      expect(result[:prompt]).to eq("Tell me a joke about the topic of pirates.")
      expect(result[:instance]).to be_a(Raif::TestTemplateTask)
    end

    it "renders different prompts for different preview methods" do
      result = task_preview.render_preview(:custom_topic)
      expect(result[:prompt]).to eq("Tell me a joke about the topic of robots.")
    end

    it "renders a system prompt from a template" do
      result = system_prompt_preview.render_preview(:default)
      expect(result[:system_prompt]).to eq("You are a comedian. Be funny and entertaining.")
      expect(result[:prompt]).to eq("Tell me a joke")
    end

    it "returns default system prompt when no template exists" do
      result = task_preview.render_preview(:default)
      expect(result[:system_prompt]).to include("You are a helpful assistant")
    end
  end
end
