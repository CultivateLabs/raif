# frozen_string_literal: true

RSpec.shared_examples "an LLM that uses OpenAI's Completions API tool formatting" do
  describe "#build_tools_parameter" do
    let(:model_completion) do
      Raif::ModelCompletion.new(
        messages: [{ role: "user", content: "Hello" }],
        llm_model_key: "open_ai_gpt_4o",
        model_api_name: "gpt-4o",
        available_model_tools: available_model_tools
      )
    end

    context "with no tools" do
      let(:available_model_tools) { [] }

      it "returns an empty array" do
        result = llm.send(:build_tools_parameter, model_completion)
        expect(result).to eq([])
      end
    end

    context "with developer-managed tools" do
      let(:available_model_tools) { [Raif::TestModelTool] }

      it "formats developer-managed tools correctly" do
        result = llm.send(:build_tools_parameter, model_completion)

        expect(result).to eq([{
          type: "function",
          function: {
            name: "test_model_tool",
            description: "Mock Tool Description",
            parameters: {
              type: "object",
              additionalProperties: false,
              properties: {
                items: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: { title: { type: "string", description: "The title of the item" }, description: { type: "string" } },
                    additionalProperties: false,
                    required: ["title", "description"]
                  }
                }
              },
              required: ["items"]
            }
          }
        }])
      end
    end

    context "with provider-managed tools" do
      let(:available_model_tools) { [Raif::ModelTools::ProviderManaged::WebSearch] }

      it "raises Raif::Errors::UnsupportedFeatureError" do
        expect do
          llm.send(:build_tools_parameter, model_completion)
        end.to raise_error(Raif::Errors::UnsupportedFeatureError)
      end
    end
  end
end
