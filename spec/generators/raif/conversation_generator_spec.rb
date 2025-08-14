# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/raif/conversation/conversation_generator"

RSpec.describe Raif::Generators::ConversationGenerator, type: :generator do
  let(:tmp_dir) { Rails.root.join("tmp", "generator_test") }

  before do
    FileUtils.rm_rf(tmp_dir)
    FileUtils.mkdir_p(tmp_dir)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "with default options" do
    before do
      run_generator ["my_conversation"]
    end

    it "creates the application conversation file if it doesn't exist" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/application_conversation.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/application_conversation.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("class ApplicationConversation < Raif::Conversation")
      expect(content).to include("# Add any shared conversation behavior here")
    end

    it "creates the conversations directory" do
      expect(File.directory?(File.join(tmp_dir, "app/models/raif/conversations"))).to be true
    end

    it "creates the conversation file with correct structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/conversations/my_conversation.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/conversations/my_conversation.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Conversations")
      expect(content).to include("class MyConversation < Raif::ApplicationConversation")
      expect(content).to include("llm_response_format :text")
      expect(content).to include("# def build_system_prompt")
      expect(content).to include("# def initial_chat_message")
      expect(content).to include("# def process_model_response_message")
    end

    it "creates the eval set file" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/conversations/my_conversation_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/conversations/my_conversation_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module EvalSets")
      expect(content).to include("module Conversations")
      expect(content).to include("class MyConversationEvalSet < Raif::Evals::EvalSet")
      expect(content).to include("bundle exec raif evals ./raif_evals/eval_sets/conversations/my_conversation_eval_set.rb")
    end

    it "displays success message with configuration instructions" do
      expect { run_generator ["another_conversation"] }.to output(/Conversation type created successfully/).to_stdout
    end
  end

  describe "with nested module names" do
    before do
      run_generator ["admin/support/chat_conversation"]
    end

    it "creates conversation file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/conversations/admin/support/chat_conversation.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/conversations/admin/support/chat_conversation.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Conversations")
      expect(content).to include("module Admin")
      expect(content).to include("module Support")
      expect(content).to include("class ChatConversation < Raif::ApplicationConversation")
    end

    it "creates eval set file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/conversations/admin/support/chat_conversation_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/conversations/admin/support/chat_conversation_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module EvalSets")
      expect(content).to include("module Conversations")
      expect(content).to include("module Admin")
      expect(content).to include("module Support")
      expect(content).to include("class ChatConversationEvalSet < Raif::Evals::EvalSet")
    end
  end

  describe "with response_format option" do
    context "when response_format is html" do
      before do
        run_generator ["my_html_conversation", "--response-format", "html"]
      end

      it "sets the response format to html" do
        content = File.read(File.join(tmp_dir, "app/models/raif/conversations/my_html_conversation.rb"))
        expect(content).to include("llm_response_format :html")
      end
    end

    context "when response_format is json" do
      before do
        run_generator ["my_json_conversation", "--response-format", "json"]
      end

      it "sets the response format to json" do
        content = File.read(File.join(tmp_dir, "app/models/raif/conversations/my_json_conversation.rb"))
        expect(content).to include("llm_response_format :json")
      end
    end

    context "when response_format is text" do
      before do
        run_generator ["my_text_conversation", "--response-format", "text"]
      end

      it "sets the response format to text" do
        content = File.read(File.join(tmp_dir, "app/models/raif/conversations/my_text_conversation.rb"))
        expect(content).to include("llm_response_format :text")
      end
    end
  end

  describe "with skip_eval_set option" do
    before do
      run_generator ["my_conversation", "--skip-eval-set"]
    end

    it "does not create the eval set file" do
      expect(File).not_to exist(File.join(tmp_dir, "raif_evals/eval_sets/conversations/my_conversation_eval_set.rb"))
    end

    it "still creates the conversation file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/conversations/my_conversation.rb"))
    end

    it "still creates the application conversation file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/application_conversation.rb"))
    end

    it "still creates the conversations directory" do
      expect(File.directory?(File.join(tmp_dir, "app/models/raif/conversations"))).to be true
    end
  end

  describe "when application conversation file already exists" do
    it "does not overwrite the existing application conversation file" do
      # First run creates the file
      run_generator ["my_conversation"]
      original_content = File.read(File.join(tmp_dir, "app/models/raif/application_conversation.rb"))

      # Second run should not overwrite it
      run_generator ["another_conversation"]
      content = File.read(File.join(tmp_dir, "app/models/raif/application_conversation.rb"))
      expect(content).to eq(original_content)
    end

    it "still creates the conversation file" do
      # First run
      run_generator ["my_conversation"]
      # Second run with different conversation name
      run_generator ["another_conversation"]

      expect(File).to exist(File.join(tmp_dir, "app/models/raif/conversations/my_conversation.rb"))
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/conversations/another_conversation.rb"))
    end
  end

  describe "when conversations directory already exists" do
    before do
      FileUtils.mkdir_p(File.join(tmp_dir, "app/models/raif/conversations"))
      run_generator ["my_conversation"]
    end

    it "does not create the directory again" do
      expect(File.directory?(File.join(tmp_dir, "app/models/raif/conversations"))).to be true
    end

    it "still creates the conversation file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/conversations/my_conversation.rb"))
    end
  end

  describe "eval_set_file_path method" do
    it "generates correct path for simple conversation name" do
      generator = described_class.new(["my_conversation"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/conversations/my_conversation_eval_set.rb"
      )
    end

    it "generates correct path for nested conversation name" do
      generator = described_class.new(["admin/support/chat_conversation"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/conversations/admin/support/chat_conversation_eval_set.rb"
      )
    end
  end

private

  def run_generator(args = [], config = {})
    described_class.start(args, config.merge(destination_root: tmp_dir))
  end
end
