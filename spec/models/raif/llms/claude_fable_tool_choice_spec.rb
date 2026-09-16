# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Claude Fable 5.1 tool choice" do
  %i[anthropic_claude_5_1_fable bedrock_claude_5_1_fable].each do |key|
    context key.to_s do
      let(:llm){ Raif.llm(key) }

      it "keeps automatic tool use available while disabling both constrained choices" do
        expect(llm.supports_native_tool_use?).to be(true)
        expect(llm.supports_forced_tool_choice?).to be(false)
        expect(llm.supports_required_tool_choice?).to be(false)
      end

      it "preserves the restriction when the API name changes to a routing alias or snapshot" do
        llm.api_name = "custom-routing-alias-20260914"
        expect { llm.build_forced_tool_choice("wikipedia_search") }
          .to raise_error(Raif::Errors::UnsupportedFeatureError, /does not support forced tool choice/)
      end

      it "rejects explicit chat choices before creating a completion" do
        [Raif::ModelTools::WikipediaSearch, :required].each do |choice|
          expect do
            expect do
              llm.chat(message: "Search for Paris", available_model_tools: [Raif::ModelTools::WikipediaSearch], tool_choice: choice)
            end.to raise_error(Raif::Errors::UnsupportedFeatureError)
          end.not_to change(Raif::ModelCompletion, :count)
        end
      end

      it "declares that required tool use cannot be faithfully enforced" do
        expect(llm.supports_faithful_required_tool_choice?([Raif::ModelTools::WikipediaSearch])).to be(false)
      end

      it "rejects forced and required tool choices before submitting a request" do
        expect { llm.build_forced_tool_choice("wikipedia_search") }
          .to raise_error(Raif::Errors::UnsupportedFeatureError, /does not support forced tool choice/)
        expect { llm.build_required_tool_choice }
          .to raise_error(Raif::Errors::UnsupportedFeatureError, /does not support required tool choice/)
      end
    end
  end
end
