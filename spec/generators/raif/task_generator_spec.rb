# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/raif/task/task_generator"

RSpec.describe Raif::Generators::TaskGenerator, type: :generator do
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
      run_generator ["MyTask"]
    end

    it "creates the application task file if it doesn't exist" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/application_task.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/application_task.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("class ApplicationTask < Raif::Task")
      expect(content).to include("# Add any shared task behavior here")
    end

    it "creates the task file with correct structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/tasks/my_task.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/tasks/my_task.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Tasks")
      expect(content).to include("class MyTask < Raif::ApplicationTask")
      expect(content).to include("llm_response_format :text")
      expect(content).to include("def build_prompt")
      expect(content).to include("raise NotImplementedError")
    end

    it "creates the eval set file" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/tasks/my_task_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/tasks/my_task_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module EvalSets")
      expect(content).to include("module Tasks")
      expect(content).to include("class MyTaskEvalSet < Raif::Evals::EvalSet")
      expect(content).to include("bundle exec raif evals ./raif_evals/eval_sets/tasks/my_task_eval_set.rb")
    end
  end

  describe "with nested module names" do
    before do
      run_generator ["Admin::Analytics::UserReport"]
    end

    it "creates task file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/tasks/admin/analytics/user_report.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/tasks/admin/analytics/user_report.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Tasks")
      expect(content).to include("module Admin")
      expect(content).to include("module Analytics")
      expect(content).to include("class UserReport < Raif::ApplicationTask")
    end

    it "creates eval set file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/tasks/admin/analytics/user_report_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/tasks/admin/analytics/user_report_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module EvalSets")
      expect(content).to include("module Tasks")
      expect(content).to include("module Admin")
      expect(content).to include("module Analytics")
      expect(content).to include("class UserReportEvalSet < Raif::Evals::EvalSet")
    end
  end

  describe "with response_format option" do
    context "when response_format is html" do
      before do
        run_generator ["my_html_task", "--response-format", "html"]
      end

      it "sets the response format to html" do
        content = File.read(File.join(tmp_dir, "app/models/raif/tasks/my_html_task.rb"))
        expect(content).to include("llm_response_format :html")
        expect(content).to include("# Optional: Set the allowed tags for the task")
        expect(content).to include("# llm_response_allowed_tags")
        expect(content).to include("# Optional: Set the allowed attributes for the task")
        expect(content).to include("# llm_response_allowed_attributes")
        expect(content).not_to include("json_response_schema do")
      end
    end

    context "when response_format is json" do
      before do
        run_generator ["my_json_task", "--response-format", "json"]
      end

      it "sets the response format to json and includes schema template" do
        content = File.read(File.join(tmp_dir, "app/models/raif/tasks/my_json_task.rb"))
        expect(content).to include("llm_response_format :json")
        expect(content).to include("json_response_schema do")
        expect(content).to include("# string :title, description:")
        expect(content).to include("# object :widget, description:")
        expect(content).to include("# array :products, description:")
      end
    end

    context "when response_format is text" do
      before do
        run_generator ["my_text_task", "--response-format", "text"]
      end

      it "sets the response format to text" do
        content = File.read(File.join(tmp_dir, "app/models/raif/tasks/my_text_task.rb"))
        expect(content).to include("llm_response_format :text")
        expect(content).not_to include("json_response_schema do")
        expect(content).to include("# Optional: Set the allowed tags for the task. Only relevant if response_format is :html.")
      end
    end
  end

  describe "with skip_eval_set option" do
    before do
      run_generator ["my_task", "--skip-eval-set"]
    end

    it "does not create the eval set file" do
      expect(File).not_to exist(File.join(tmp_dir, "raif_evals/eval_sets/tasks/my_task_eval_set.rb"))
    end

    it "still creates the task file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/tasks/my_task.rb"))
    end

    it "still creates the application task file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/application_task.rb"))
    end
  end

  describe "when application task file already exists" do
    it "does not overwrite the existing application task file" do
      # First run creates the file
      run_generator ["my_task"]
      original_content = File.read(File.join(tmp_dir, "app/models/raif/application_task.rb"))

      # Second run should not overwrite it
      run_generator ["another_task"]
      content = File.read(File.join(tmp_dir, "app/models/raif/application_task.rb"))
      expect(content).to eq(original_content)
    end

    it "still creates the task file" do
      # First run
      run_generator ["my_task"]
      # Second run with different task name
      run_generator ["another_task"]

      expect(File).to exist(File.join(tmp_dir, "app/models/raif/tasks/my_task.rb"))
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/tasks/another_task.rb"))
    end
  end

  describe "show_instructions" do
    it "displays completion message" do
      expect { run_generator ["my_task"] }.to output(/Task created!/).to_stdout
    end
  end

  describe "eval_set_file_path method" do
    it "generates correct path for simple task name" do
      generator = described_class.new(["my_task"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/tasks/my_task_eval_set.rb"
      )
    end

    it "generates correct path for nested task name" do
      generator = described_class.new(["admin/analytics/user_report"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/tasks/admin/analytics/user_report_eval_set.rb"
      )
    end
  end

private

  def run_generator(args = [], config = {})
    described_class.start(args, config.merge(destination_root: tmp_dir))
  end
end
