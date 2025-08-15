# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/raif/eval_set/eval_set_generator"

RSpec.describe Raif::Generators::EvalSetGenerator, type: :generator do
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
      run_generator ["my_eval_set"]
    end

    it "creates the eval set file with correct structure" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/my_eval_set_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/my_eval_set_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Evals")
      expect(content).to include("class MyEvalSetEvalSet < Raif::Evals::EvalSet")
      expect(content).to include("bundle exec raif evals ./raif_evals/eval_sets/my_eval_set_eval_set.rb")
      expect(content).to include("setup do")
      expect(content).to include("teardown do")
      expect(content).to include("eval \"description of your eval\" do")
      expect(content).to include("# Your eval code here")
    end

    it "displays instructions for running eval sets" do
      expect { run_generator ["another_eval_set"] }.to output(/Eval set created!/).to_stdout
    end
  end

  describe "with nested module names" do
    before do
      run_generator ["admin/analytics/report_eval_set"]
    end

    it "creates eval set file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/admin/analytics/report_eval_set_eval_set.rb"))

      content = File.read(File.join(tmp_dir, "raif_evals/eval_sets/admin/analytics/report_eval_set_eval_set.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module Evals")
      expect(content).to include("module Admin")
      expect(content).to include("module Analytics")
      expect(content).to include("class ReportEvalSetEvalSet < Raif::Evals::EvalSet")
      expect(content).to include("bundle exec raif evals ./raif_evals/eval_sets/admin/analytics/report_eval_set_eval_set.rb")
    end
  end

  describe "eval_set_file_path method" do
    it "generates correct path for simple eval set name" do
      generator = described_class.new(["my_eval_set"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/my_eval_set_eval_set.rb"
      )
    end

    it "generates correct path for nested eval set name" do
      generator = described_class.new(["admin/analytics/report_eval_set"])
      expect(generator.send(:eval_set_file_path)).to eq(
        "raif_evals/eval_sets/admin/analytics/report_eval_set_eval_set.rb"
      )
    end
  end

  describe "multiple runs" do
    it "creates multiple eval set files without conflicts" do
      run_generator ["first_eval_set"]
      run_generator ["second_eval_set"]

      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/first_eval_set_eval_set.rb"))
      expect(File).to exist(File.join(tmp_dir, "raif_evals/eval_sets/second_eval_set_eval_set.rb"))
    end
  end

private

  def run_generator(args = [], config = {})
    described_class.start(args, config.merge(destination_root: tmp_dir))
  end
end
