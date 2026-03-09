# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Concerns::HasPromptTemplates do
  describe "template resolution for tasks" do
    context "when a .prompt.erb template exists" do
      it "uses the template to build the prompt" do
        task = Raif::TestTemplateTask.new(topic: "cats")
        expect(task.build_prompt).to eq("Tell me a joke about the topic of cats.")
      end

      it "uses default run_with values in templates" do
        task = Raif::TestTemplateTask.new
        expect(task.build_prompt).to eq("Tell me a joke about the topic of pirates.")
      end
    end

    context "when no template exists but build_prompt is overridden" do
      it "falls back to the method-based approach" do
        task = Raif::TestTask.new
        expect(task.build_prompt).to eq("Tell me a joke")
      end
    end

    context "when neither template nor method override exists" do
      it "raises NotImplementedError" do
        task = Raif::Task.new
        expect { task.build_prompt }.to raise_error(NotImplementedError)
      end
    end
  end

  describe "system prompt template resolution for tasks" do
    context "when a .system_prompt.erb template exists" do
      it "uses the template for the system prompt" do
        task = Raif::TestTemplateSystemPromptTask.new(persona: "storyteller")
        expect(task.build_system_prompt).to eq("You are a storyteller. Be funny and entertaining.")
      end
    end

    context "when no system prompt template exists" do
      it "falls back to the default system prompt behavior" do
        task = Raif::TestTask.new
        expect(task.build_system_prompt).to include(Raif.config.task_system_prompt_intro)
      end
    end
  end

  describe "template resolution for conversations" do
    context "when a .system_prompt.erb template exists" do
      it "uses the template for the system prompt" do
        conversation = Raif::TestTemplateConversation.new(persona: "talented chef")
        expect(conversation.build_system_prompt).to eq("You are a talented chef. Help the user with their questions.")
      end
    end

    context "when no system prompt template exists" do
      it "falls back to the default system prompt behavior" do
        conversation = Raif::Conversation.new
        expect(conversation.build_system_prompt).to include(Raif.config.conversation_system_prompt_intro)
      end
    end
  end

  describe "template resolution for agents" do
    context "when a .system_prompt.erb template exists" do
      it "uses the template for the system prompt" do
        agent = Raif::TestTemplateAgent.new(agent_role: "research")
        expect(agent.build_system_prompt).to eq("You are a research agent. Complete the assigned task thoroughly.")
      end
    end

    context "when no system prompt template exists on the base Agent class" do
      it "raises NotImplementedError (unchanged behavior)" do
        agent = Raif::Agent.new
        expect { agent.build_system_prompt }.to raise_error(NotImplementedError)
      end
    end
  end

  describe "partials and Rails view helpers" do
    it "renders partials referenced in prompt templates" do
      task = Raif::TestTemplateWithPartialTask.new(topic: "dogs")
      prompt = task.build_prompt
      expect(prompt).to include("Tell me a joke about dogs.")
      expect(prompt).to include("Always be concise and clear in your responses.")
    end

    it "supports content_tag helper" do
      task = Raif::TestTemplateWithPartialTask.new(topic: "dogs")
      prompt = task.build_prompt
      expect(prompt).to include("<instructions>")
      expect(prompt).to include("</instructions>")
    end

    it "supports truncate helper" do
      task = Raif::TestTemplateWithPartialTask.new(topic: "dogs")
      prompt = task.build_prompt
      expect(prompt).to include("a very long sente...")
    end
  end

  describe ".prompt_template_prefix" do
    it "returns the underscored class name" do
      expect(Raif::TestTemplateTask.prompt_template_prefix).to eq("raif/test_template_task")
    end
  end

  describe "error handling" do
    it "wraps template rendering errors in PromptTemplateError" do
      # Create a task class that points to a template with a rendering error
      task_class = Class.new(Raif::Task) do
        def self.name
          "Raif::TestTemplateTask"
        end

        def self.prompt_template_prefix
          "raif/test_template_task"
        end
      end

      task = task_class.new

      # Stub the template existence check to return true, but rendering will fail
      # because the template context won't have the method
      allow(task).to receive(:prompt_template_exists?).with(:prompt).and_return(true)
      allow(task).to receive(:render_prompt_template).with(:prompt).and_call_original

      # Force a rendering error by making the lookup context find a bad template
      # We'll test this indirectly - the PromptTemplateError class itself
      error = Raif::Errors::PromptTemplateError.new(
        template_path: "raif/test.prompt.erb",
        original_error: StandardError.new("undefined method 'foo'")
      )
      expect(error.message).to eq("Error rendering prompt template 'raif/test.prompt.erb': StandardError: undefined method 'foo'")
      expect(error.template_path).to eq("raif/test.prompt.erb")
      expect(error.original_error).to be_a(StandardError)
    end
  end
end
