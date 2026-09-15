# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adapter tool choice capabilities" do
  [
    Raif::Llms::Anthropic, Raif::Llms::Bedrock, Raif::Llms::BedrockMantle,
    Raif::Llms::OpenAiCompletions, Raif::Llms::OpenAiResponses,
    Raif::Llms::OpenRouter, Raif::Llms::XAi, Raif::Llms::Google
  ].each do |adapter|
    context adapter.name do
      let(:llm){ adapter.new(key: :custom, api_name: "custom-model") }

      it "preserves formatted tool choices for custom models without capability settings" do
        expect(llm.build_forced_tool_choice("search")).to be_present
        expect(llm.build_required_tool_choice).to be_present
      end

      it "honors a forced-tool restriction without disabling required choice" do
        llm.provider_settings[:supports_forced_tool_choice] = false
        expect { llm.build_forced_tool_choice("search") }
          .to raise_error(Raif::Errors::UnsupportedFeatureError, /does not support forced tool choice/)
        expect(llm.build_required_tool_choice).to be_present
      end

      it "honors a required-tool restriction without disabling forced choice" do
        llm.provider_settings[:supports_required_tool_choice] = false
        expect { llm.build_required_tool_choice }
          .to raise_error(Raif::Errors::UnsupportedFeatureError, /does not support required tool choice/)
        expect(llm.build_forced_tool_choice("search")).to be_present
      end
    end
  end
end
