# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/raif/model_tool/model_tool_generator"

RSpec.describe Raif::Generators::ModelToolGenerator, type: :generator do
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
      run_generator ["my_tool"]
    end

    it "creates the model tool file with correct structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/model_tools/my_tool.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/my_tool.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module ModelTools")
      expect(content).to include("class MyTool < Raif::ModelTool")
      expect(content).to include("tool_description do")
      expect(content).to include("tool_arguments_schema do")
      expect(content).to include("example_model_invocation do")
      expect(content).to include("def observation_for_invocation(tool_invocation)")
      expect(content).to include("def triggers_observation_to_model?")
      expect(content).to include("def process_invocation(tool_invocation)")
      expect(content).to include("Wikipedia Search Tool:")
      expect(content).to include("Fetch URL Tool:")
    end

    it "creates the view partial file with correct structure" do
      expect(File).to exist(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_my_tool.html.erb"))

      content = File.read(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_my_tool.html.erb"))
      expect(content).to include("<div class=\"raif-model-tool-invocation\">")
      expect(content).to include("<%= my_tool.tool_type.demodulize.titleize %>")
      expect(content).to include("<%= JSON.pretty_generate(my_tool.result || {}) %>")
      expect(content).to include("Edit this file in")
      expect(content).to include("This partial is used to render a model tool invocation")
    end

    it "displays success message with file paths" do
      expect { run_generator ["another_tool"] }.to output(/Model tool created successfully/).to_stdout
    end
  end

  describe "with nested module names" do
    before do
      run_generator ["admin/analytics/report_tool"]
    end

    it "creates model tool file with proper nested module structure" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/model_tools/admin/analytics/report_tool.rb"))

      content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/admin/analytics/report_tool.rb"))
      expect(content).to include("module Raif")
      expect(content).to include("module ModelTools")
      expect(content).to include("module Admin")
      expect(content).to include("module Analytics")
      expect(content).to include("class ReportTool < Raif::ModelTool")
    end

    it "creates view partial file with proper nested directory structure" do
      expect(File).to exist(File.join(tmp_dir, "app/views/raif/model_tool_invocations/admin/analytics/_report_tool.html.erb"))

      content = File.read(File.join(tmp_dir, "app/views/raif/model_tool_invocations/admin/analytics/_report_tool.html.erb"))
      expect(content).to include("<div class=\"raif-model-tool-invocation\">")
      expect(content).to include("<%= report_tool.tool_type.demodulize.titleize %>")
      expect(content).to include("<%= JSON.pretty_generate(report_tool.result || {}) %>")
    end
  end

  describe "multiple model tools" do
    before do
      run_generator ["search_tool"]
      run_generator ["calculation_tool"]
    end

    it "creates multiple model tool files without conflicts" do
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/model_tools/search_tool.rb"))
      expect(File).to exist(File.join(tmp_dir, "app/models/raif/model_tools/calculation_tool.rb"))
    end

    it "creates multiple view partial files without conflicts" do
      expect(File).to exist(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_search_tool.html.erb"))
      expect(File).to exist(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_calculation_tool.html.erb"))
    end

    it "each model tool has unique class names" do
      search_content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/search_tool.rb"))
      calc_content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/calculation_tool.rb"))

      expect(search_content).to include("class SearchTool < Raif::ModelTool")
      expect(calc_content).to include("class CalculationTool < Raif::ModelTool")
    end

    it "each view partial references the correct variable name" do
      search_content = File.read(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_search_tool.html.erb"))
      calc_content = File.read(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_calculation_tool.html.erb"))

      expect(search_content).to include("<%= search_tool.tool_type.demodulize.titleize %>")
      expect(search_content).to include("JSON.pretty_generate(search_tool.result")

      expect(calc_content).to include("<%= calculation_tool.tool_type.demodulize.titleize %>")
      expect(calc_content).to include("JSON.pretty_generate(calculation_tool.result")
    end
  end

  describe "file contents validation" do
    before do
      run_generator ["example_tool"]
    end

    it "includes comprehensive tool_arguments_schema examples" do
      content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/example_tool.rb"))
      expect(content).to include("string :title, description:")
      expect(content).to include("object :widget, description:")
      expect(content).to include("boolean :is_red, description:")
      expect(content).to include("integer :rating, description:")
      expect(content).to include("array :tags, description:")
      expect(content).to include("array :products, description:")
      expect(content).to include("number :price, description:")
    end

    it "includes example_model_invocation with tool_name reference" do
      content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/example_tool.rb"))
      expect(content).to include("example_model_invocation do")
      expect(content).to include("\"name\": tool_name")
      expect(content).to include("\"arguments\": {}")
    end

    it "includes comprehensive process_invocation method comments" do
      content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/example_tool.rb"))
      expect(content).to include("# Extract arguments from tool_invocation.tool_arguments")
      expect(content).to include("# query = tool_invocation.tool_arguments[\"query\"]")
      expect(content).to include("# tool_invocation.update!")
      expect(content).to include("# tool_invocation.result")
    end

    it "includes helpful links to example implementations" do
      content = File.read(File.join(tmp_dir, "app/models/raif/model_tools/example_tool.rb"))
      expect(content).to include("# For example tool implementations, see:")
      expect(content).to include("# Wikipedia Search Tool: https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/wikipedia_search.rb")
      expect(content).to include("# Fetch URL Tool: https://github.com/CultivateLabs/raif/blob/main/app/models/raif/model_tools/fetch_url.rb")
    end
  end

  describe "view partial contents validation" do
    before do
      run_generator ["display_tool"]
    end

    it "includes helpful template comments" do
      content = File.read(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_display_tool.html.erb"))
      expect(content).to include("This partial is used to render a model tool invocation to the user")
      expect(content).to include("you can override the `renderable?` method in your model tool class to return false")
    end

    it "includes the correct ERB structure for displaying results" do
      content = File.read(File.join(tmp_dir, "app/views/raif/model_tool_invocations/_display_tool.html.erb"))
      expect(content).to include("<div class=\"raif-model-tool-invocation\">")
      expect(content).to include("<h5><%= display_tool.tool_type.demodulize.titleize %> Result</h5>")
      expect(content).to include("<pre><%= JSON.pretty_generate(display_tool.result || {}) %></pre>")
      expect(content).to include("Edit this file in <code><%= __FILE__ %></code>")
    end
  end

private

  def run_generator(args = [], config = {})
    described_class.start(args, config.merge(destination_root: tmp_dir))
  end
end
