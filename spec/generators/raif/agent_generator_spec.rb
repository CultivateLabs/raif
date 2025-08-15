# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/raif/agent/agent_generator"

RSpec.describe Raif::Generators::AgentGenerator, type: :generator do
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
      run_generator ["my_agent"]
    end

    it "creates the application agent file if it doesn't exist" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/application_agent.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/application_agent.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("class ApplicationAgent < Raif::Agent")
      expect(content).to include("# Add any shared agent behavior here")
    end

    it "creates the agents directory" do
      expect(File.directory?(File.join(tmp_dir, "app/models/raif/agents"))).to be true
    end

    it "creates the agent file with correct structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/agents/my_agent.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/agents/my_agent.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Agents")
      expect(content).to include("class MyAgent < Raif::ApplicationAgent")
      expect(content).to include("def build_system_prompt")
      expect(content).to include("def process_iteration_model_completion")
      expect(content).to include("# def populate_default_model_tools")
    end

    it "creates the eval set file" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/agents/my_agent_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/agents/my_agent_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Evals")
      expect(content).to include("module Agents")
      expect(content).to include("class MyAgentEvalSet < Raif::Evals::EvalSet")
      expect(content).to include("bundle exec raif evals ./raif_evals/eval_sets/agents/my_agent_eval_set.rb")
    end

    it "displays completion message" do
      expect { run_generator ["another_agent"] }.to output(/Agent created!/).to_stdout
    end
  end

  describe "with nested module names" do
    before do
      run_generator ["admin/analytics/report_agent"]
    end

    it "creates agent file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/agents/admin/analytics/report_agent.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/agents/admin/analytics/report_agent.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Agents")
      expect(content).to include("module Admin")
      expect(content).to include("module Analytics")
      expect(content).to include("class ReportAgent < Raif::ApplicationAgent")
    end

    it "creates eval set file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/agents/admin/analytics/report_agent_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/agents/admin/analytics/report_agent_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Evals")
      expect(content).to include("module Agents")
      expect(content).to include("module Admin")
      expect(content).to include("module Analytics")
      expect(content).to include("class ReportAgentEvalSet < Raif::Evals::EvalSet")
    end
  end

  describe "with skip_eval_set option" do
    before do
      run_generator ["my_agent", "--skip-eval-set"]
    end

    it "does not create the eval set file" do
      expect(File).not_to exist(File.join(tmp_dir, "raif_evals/eval_sets/agents/my_agent_eval_set.rb"))
    end

    it "still creates the agent file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/agents/my_agent.rb"))
    end

    it "still creates the application agent file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/application_agent.rb"))
    end

    it "still creates the agents directory" do
      expect(File.directory?(File.join(tmp_dir, "app/models/raif/agents"))).to be true
    end
  end

  describe "when application agent file already exists" do
    it "does not overwrite the existing application agent file" do
      # First run creates the file
      run_generator ["my_agent"]
      original_content = File.read(File.join(tmp_dir, "app/models/raif/application_agent.rb"))

      # Second run should not overwrite it
      run_generator ["another_agent"]
      content = File.read(File.join(tmp_dir, "app/models/raif/application_agent.rb"))
      expect(content).to eq(original_content)
    end

    it "still creates the agent file" do
      # First run
      run_generator ["my_agent"]
      # Second run with different agent name
      run_generator ["another_agent"]

      expect(File).to exist(File.join(tmp_dir, "app/models/raif/agents/my_agent.rb"))
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/agents/another_agent.rb"))
    end
  end

  describe "when agents directory already exists" do
    before do
      FileUtils.mkdir_p(File.join(tmp_dir, "app/models/raif/agents"))
      run_generator ["my_agent"]
    end

    it "does not create the directory again" do
      expect(File.directory?(File.join(tmp_dir, "app/models/raif/agents"))).to be true
    end

    it "still creates the agent file" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/agents/my_agent.rb"))
    end
  end

  describe "eval_set_file_path method" do
    it "generates correct path for simple agent name" do
      generator = described_class.new(["my_agent"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/agents/my_agent_eval_set.rb"
      )
    end

    it "generates correct path for nested agent name" do
      generator = described_class.new(["admin/analytics/report_agent"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/agents/admin/analytics/report_agent_eval_set.rb"
      )
    end
  end

private

  def run_generator(args = [], config = {})
    described_class.start(args, config.merge(destination_root: tmp_dir))
  end
end
