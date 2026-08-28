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
  end
end
