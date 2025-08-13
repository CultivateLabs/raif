# frozen_string_literal: true

require "rails_helper"
require "generators/raif/eval_set/eval_set_generator"

RSpec.describe Raif::Generators::EvalSetGenerator do
  # Since we're an engine, we'll test the generator manually
  # without relying on generator test helpers

  let(:generator) { described_class.new(["CustomerSupport"]) }
  let(:test_dir) { Rails.root.join("tmp", "generator_test") }

  before do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
    allow(generator).to receive(:destination_root).and_return(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "template rendering" do
    it "generates correct content for simple eval set" do
      generator = described_class.new(["CustomerSupport"])
      allow(generator).to receive(:destination_root).and_return(test_dir)

      # Manually set up the instance variables the template needs
      generator.instance_variable_set(:@class_path, [])
      generator.instance_variable_set(:@class_name_without_namespace, "CustomerSupport")
      generator.instance_variable_set(:@full_class_name, "CustomerSupportEvalSet")

      # Read and render the template
      template_path = File.expand_path("../../../lib/generators/raif/eval_set/templates/eval_set.rb.erb", __dir__)
      template = ERB.new(File.read(template_path))
      result = template.result(generator.instance_eval { binding })

      expect(result).to include("class CustomerSupportEvalSet < Raif::Evals::EvalSet")
      expect(result).to include("setup do")
      expect(result).to include("teardown do")
      expect(result).to include('eval "description of your eval" do')
    end

    it "generates correct content for namespaced eval set" do
      generator = described_class.new(["MyModule::CustomerSupport"])
      allow(generator).to receive(:destination_root).and_return(test_dir)

      # Manually set up the instance variables
      generator.instance_variable_set(:@class_path, ["MyModule"])
      generator.instance_variable_set(:@class_name_without_namespace, "CustomerSupport")
      generator.instance_variable_set(:@full_class_name, "MyModule::CustomerSupportEvalSet")

      # Read and render the template
      template_path = File.expand_path("../../../lib/generators/raif/eval_set/templates/eval_set.rb.erb", __dir__)
      template = ERB.new(File.read(template_path))
      result = template.result(generator.instance_eval { binding })

      expect(result).to include("class MyModule::CustomerSupportEvalSet < Raif::Evals::EvalSet")
      expect(result).to include("setup do")
      expect(result).to include("teardown do")
      expect(result).to include('eval "description of your eval" do')
    end
  end
end
