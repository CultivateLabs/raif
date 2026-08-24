# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/raif/evals/setup/setup_generator"

RSpec.describe Raif::Generators::Evals::SetupGenerator, type: :generator do
  let(:tmp_dir) { Rails.root.join("tmp", "evals_setup_generator_test") }
  let(:gitignore_path) { File.join(tmp_dir, "raif_evals/results/.gitignore") }

  before do
    FileUtils.rm_rf(tmp_dir)
    FileUtils.mkdir_p(tmp_dir)
  end

  after { FileUtils.rm_rf(tmp_dir) }

  it "creates the eval directories and setup file" do
    run_generator

    %w[raif_evals raif_evals/eval_sets raif_evals/files raif_evals/datasets raif_evals/results].each do |dir|
      expect(Dir).to exist(File.join(tmp_dir, dir))
    end

    expect(File.read(File.join(tmp_dir, "raif_evals/setup.rb")))
      .to include("This file is loaded at the start of a run of your evals")
  end

  describe "the results .gitignore" do
    it "ignores results and names the run log pattern separately" do
      run_generator

      contents = File.read(gitignore_path)
      expect(contents.lines.map(&:chomp)).to include("*", "!.gitignore", "*.partial.jsonl")
    end

    # Re-running is how an existing install picks the pattern up.
    it "appends the run log pattern to a .gitignore that predates it" do
      FileUtils.mkdir_p(File.dirname(gitignore_path))
      File.write(gitignore_path, "*\n!.gitignore\n")

      run_generator

      contents = File.read(gitignore_path)
      expect(contents).to start_with("*\n!.gitignore\n")
      expect(contents).to include("*.partial.jsonl")
    end

    it "leaves a .gitignore that already names the pattern alone" do
      FileUtils.mkdir_p(File.dirname(gitignore_path))
      File.write(gitignore_path, "*.partial.jsonl\n")

      run_generator
      run_generator

      expect(File.read(gitignore_path)).to eq("*.partial.jsonl\n")
    end
  end

private

  def run_generator(args = [], config = {})
    described_class.start(args, config.merge(destination_root: tmp_dir))
  end
end
