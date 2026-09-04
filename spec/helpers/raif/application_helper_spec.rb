# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ApplicationHelper, type: :helper do
  describe "#llm_model_options" do
    it "labels each option with the model's name and sorts by label" do
      html = helper.llm_model_options

      Raif.available_llm_keys.each do |key|
        llm = Raif.llm(key)
        expect(html).to include(%(<option value="#{key}">#{ERB::Util.html_escape(llm.name)}</option>))
      end

      labels = html.scan(/<option value="[^"]+">([^<]+)<\/option>/).flatten
      expect(labels).to eq(labels.sort)
    end

    it "marks the selected key" do
      key = Raif.available_llm_keys.first
      expect(helper.llm_model_options(selected: key)).to include(%(<option selected="selected" value="#{key}">))
    end

    it "does not trigger the one time deprecation warning" do
      Raif.register_llm(Raif::Llms::TestLlm, key: :raif_deprecated_helper_llm, api_name: "x", display_name: "Deprecated Helper",
        deprecated: true, retirement_date: Date.new(2027, 1, 1), replacement_key: :raif_test_llm)
      Raif.reset_deprecation_warnings!

      expect(Raif.logger).to_not receive(:warn)

      helper.llm_model_options
    ensure
      Raif.llm_registry.delete(:raif_deprecated_helper_llm)
    end
  end
end
