# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Raif::Task run_with", type: :model do
  # Create a test task class with run_with
  before do
    stub_const("Raif::TaskRunArgsTestTask", Class.new(Raif::Task) do
      run_with :conversation
      run_with :user
      run_with :options
      run_with :count

      attr_accessor :unpersisted_arg

      def build_prompt
        "Test prompt"
      end

      def build_system_prompt
        "Test system prompt"
      end
    end)
  end

  let(:test_task_class) { Raif::TaskRunArgsTestTask }

  let(:user) { FB.create(:raif_test_user) }
  let(:conversation) { FB.create(:raif_conversation, creator: user) }

  describe ".run_with" do
    it "adds the argument to _run_with_args" do
      expect(test_task_class._run_with_args).to include(:conversation, :user, :options, :count)
    end

    it "defines getter and setter methods" do
      task = test_task_class.new
      expect(task).to respond_to(:conversation)
      expect(task).to respond_to(:conversation=)
      expect(task).to respond_to(:user)
      expect(task).to respond_to(:user=)
      expect(task).to respond_to(:options)
      expect(task).to respond_to(:options=)
      expect(task).to respond_to(:count)
      expect(task).to respond_to(:count=)
    end
  end

  describe ".run with run_with" do
    it "serializes ActiveRecord objects to GIDs" do
      stub_raif_task(test_task_class) do |_messages|
        "Test response"
      end

      task = test_task_class.run(
        creator: user,
        conversation: conversation,
        user: user,
        options: { include_summary: true },
        count: 42
      )

      expect(task.run_with["conversation"]).to eq(conversation.to_global_id.to_s)
      expect(task.run_with["user"]).to eq(user.to_global_id.to_s)
      expect(task.run_with["options"]).to eq({ "include_summary" => true })
      expect(task.run_with["count"]).to eq(42)

      expect(task.conversation).to eq(conversation)
      expect(task.user).to eq(user)
      expect(task.options).to eq({ include_summary: true })
      expect(task.count).to eq(42)

      # Load a fresh instance from the database, values should be the same
      t2 = test_task_class.find(task.id)
      expect(t2.conversation).to eq(conversation)
      expect(t2.user).to eq(user)
      expect(t2.options).to eq({ "include_summary" => true })
      expect(t2.count).to eq(42)
    end

    it "only serializes declared run_with" do
      stub_raif_task(test_task_class) do |_messages|
        "Test response"
      end

      task = test_task_class.run(
        creator: user,
        conversation: conversation,
        unpersisted_arg: "Unpersisted arg"
      )

      expect(task).to be_persisted
      expect(task.run_with.keys).to include("conversation")
      expect(task.run_with.keys).not_to include("unpersisted_arg")
    end
  end

  describe "accessing run_with after reload" do
    let(:task) do
      stub_raif_task(test_task_class) do |_messages|
        "Test response"
      end

      test_task_class.run(
        creator: user,
        conversation: conversation,
        user: user,
        options: { include_summary: true },
        count: 42
      )
    end

    it "deserializes GIDs back to ActiveRecord objects" do
      reloaded_task = test_task_class.find(task.id)

      expect(reloaded_task.conversation).to eq(conversation)
      expect(reloaded_task.user).to eq(user)
      expect(reloaded_task.options).to eq({ "include_summary" => true })
      expect(reloaded_task.count).to eq(42)
    end

    it "caches deserialized values" do
      reloaded_task = test_task_class.find(task.id)

      # First access deserializes
      conv1 = reloaded_task.conversation
      # Second access should use cached value
      conv2 = reloaded_task.conversation

      expect(conv1.object_id).to eq(conv2.object_id) # Same object reference
    end

    it "handles missing objects gracefully" do
      conversation.destroy
      reloaded_task = test_task_class.find(task.id)

      expect(reloaded_task.conversation).to be_nil
    end
  end

  describe "using run_with in prompts" do
    it "can access run_with in build_prompt" do
      stub_const("Raif::TaskPromptTestTask", Class.new(Raif::Task) do
        run_with :title
        run_with :document

        attr_accessor :unpersisted_arg

        def build_prompt
          "Summarize: #{title} - #{document.content} - #{unpersisted_arg}"
        end

        def build_system_prompt
          "Test system prompt"
        end
      end)

      task_class = Raif::TaskPromptTestTask
      document = Document.create(title: "Doc Title", content: "Article content here")

      stub_raif_task(task_class) do |_messages|
        "Summary"
      end

      task = task_class.run(
        creator: user,
        title: "Test Article",
        document: document,
        unpersisted_arg: "Unpersisted arg"
      )

      expect(task.prompt).to eq("Summarize: Test Article - Article content here - Unpersisted arg")
    end
  end

  describe "inheritance" do
    it "inherits run_with from parent class" do
      parent_class = Class.new(Raif::Task) do
        run_with :parent_arg
        run_with :parent_arg2
      end

      child_class = Class.new(parent_class) do
        run_with :child_arg
        run_with :child_arg2

        def build_prompt
          "Test"
        end

        def build_system_prompt
          "Test"
        end
      end

      expect(child_class._run_with_args).to include(:parent_arg, :parent_arg2, :child_arg, :child_arg2)
    end

    it "does not contaminate sibling classes" do
      stub_const("TaskA", Class.new(Raif::Task) do
        run_with :arg_a
      end)

      stub_const("TaskB", Class.new(Raif::Task) do
        run_with :arg_b
        run_with :arg_c
      end)

      expect(TaskA._run_with_args).to eq([:arg_a])
      expect(TaskB._run_with_args).to eq([:arg_b, :arg_c])
      expect(Raif::Task._run_with_args).to eq([])
    end
  end

  describe ".having_run_with" do
    let(:user1) { FB.create(:raif_test_user) }
    let(:user2) { FB.create(:raif_test_user) }
    let(:conversation1) { FB.create(:raif_conversation, creator: user1) }
    let(:conversation2) { FB.create(:raif_conversation, creator: user2) }

    let!(:task1) do
      stub_raif_task(test_task_class) { "Response 1" }
      test_task_class.run(
        creator: user1,
        conversation: conversation1,
        user: user1,
        options: { include_summary: true },
        count: 42
      )
    end

    let!(:task2) do
      stub_raif_task(test_task_class) { "Response 2" }
      test_task_class.run(
        creator: user2,
        conversation: conversation2,
        user: user2,
        options: { include_summary: false },
        count: 99
      )
    end

    let!(:task3) do
      stub_raif_task(test_task_class) { "Response 3" }
      test_task_class.run(
        creator: user1,
        conversation: conversation1,
        user: user1,
        options: { include_summary: true },
        count: 42
      )
    end

    it "returns all records when no arguments provided" do
      results = test_task_class.having_run_with
      expect(results).to match_array([task1, task2, task3])
    end

    it "queries by ActiveRecord object (serialized as GID)" do
      results = test_task_class.having_run_with(user: user1)
      expect(results).to match_array([task1, task3])
    end

    it "queries by primitive values" do
      results = test_task_class.having_run_with(count: 42)
      expect(results).to match_array([task1, task3])
    end

    it "queries by hash values" do
      results = test_task_class.having_run_with(options: { include_summary: true })
      expect(results).to match_array([task1, task3])
    end

    it "queries by multiple arguments (AND logic)" do
      results = test_task_class.having_run_with(
        user: user1,
        count: 42
      )
      expect(results).to match_array([task1, task3])
    end

    it "queries by all declared arguments" do
      results = test_task_class.having_run_with(
        conversation: conversation1,
        user: user1,
        options: { include_summary: true },
        count: 42
      )
      expect(results).to match_array([task1, task3])
    end

    it "returns empty when no matches found" do
      results = test_task_class.having_run_with(count: 999)
      expect(results).to be_empty
    end

    it "is chainable with other scopes" do
      results = test_task_class
        .having_run_with(user: user1)
        .where(id: task1.id)

      expect(results).to eq([task1])
    end
  end
end
