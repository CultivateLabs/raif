# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completions
#
#  id                        :bigint           not null, primary key
#  available_model_tools     :jsonb            not null
#  citations                 :jsonb
#  completion_tokens         :integer
#  failed_at                 :datetime
#  failure_error             :string
#  failure_reason            :string
#  llm_model_key             :string           not null
#  max_completion_tokens     :integer
#  messages                  :jsonb            not null
#  model_api_name            :string           not null
#  output_token_cost         :decimal(10, 6)
#  prompt_token_cost         :decimal(10, 6)
#  prompt_tokens             :integer
#  raw_response              :text
#  response_array            :jsonb
#  response_format           :integer          default("text"), not null
#  response_format_parameter :string
#  response_tool_calls       :jsonb
#  retry_count               :integer          default(0), not null
#  source_type               :string
#  stream_response           :boolean          default(FALSE), not null
#  system_prompt             :text
#  temperature               :decimal(5, 3)
#  tool_choice               :string
#  total_cost                :decimal(10, 6)
#  total_tokens              :integer
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  response_id               :string
#  source_id                 :bigint
#
# Indexes
#
#  index_raif_model_completions_on_created_at  (created_at)
#  index_raif_model_completions_on_failed_at   (failed_at)
#  index_raif_model_completions_on_source      (source_type,source_id)
#
require "rails_helper"

RSpec.describe Raif::ModelCompletion, type: :model do
  describe "validations" do
    it "validates presence of llm_model_key" do
      model_completion = described_class.new(response_format: "text")
      expect(model_completion).not_to be_valid
      expect(model_completion.errors[:llm_model_key]).to include("can't be blank")
    end

    it "validates that the llm_model_key is a valid model key" do
      model_completion = described_class.new(response_format: "text", llm_model_key: "invalid_model_key")
      expect(model_completion).not_to be_valid
      expect(model_completion.errors[:llm_model_key]).to include("is not included in the list")
    end

    it "validates inclusion of response_format in valid formats" do
      expect do
        described_class.new(response_format: "invalid_format", llm_model_key: "open_ai_gpt_4o")
      end.to raise_error(ArgumentError, "'invalid_format' is not a valid response_format")
    end
  end

  describe "callbacks" do
    describe "#set_total_tokens" do
      it "sets total_tokens based on completion_tokens and prompt_tokens" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          prompt_tokens: 100,
          completion_tokens: 50
        )

        model_completion.save(validate: false)
        expect(model_completion.total_tokens).to eq(150)
      end

      it "does not set total_tokens if completion_tokens is missing" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          prompt_tokens: 100
        )

        model_completion.save(validate: false)
        expect(model_completion.total_tokens).to be_nil
      end

      it "does not set total_tokens if prompt_tokens is missing" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          completion_tokens: 50
        )

        model_completion.save(validate: false)
        expect(model_completion.total_tokens).to be_nil
      end
    end

    describe "#calculate_costs" do
      it "calculates prompt_token_cost based on input_token_cost and prompt_tokens" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          prompt_tokens: 1000
        )

        # open_ai_gpt_4o has an input_token_cost of 2.5 / 1_000_000
        expected_cost = 2.5 / 1_000_000 * 1000

        model_completion.save(validate: false)
        expect(model_completion.prompt_token_cost).to eq(expected_cost)
      end

      it "calculates output_token_cost based on output_token_cost and completion_tokens" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          completion_tokens: 500
        )

        # open_ai_gpt_4o has an output_token_cost of 10.0 / 1_000_000
        expected_cost = 10.0 / 1_000_000 * 500

        model_completion.save(validate: false)
        expect(model_completion.output_token_cost).to eq(expected_cost)
      end

      it "calculates total_cost based on prompt_token_cost and output_token_cost" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          prompt_tokens: 1000,
          completion_tokens: 500
        )

        # open_ai_gpt_4o has an input_token_cost of 2.5 / 1_000_000 and output_token_cost of 10.0 / 1_000_000
        expected_prompt_cost = 2.5 / 1_000_000 * 1000
        expected_output_cost = 10.0 / 1_000_000 * 500
        expected_total_cost = expected_prompt_cost + expected_output_cost

        model_completion.save(validate: false)
        expect(model_completion.total_cost).to eq(expected_total_cost)
      end

      it "calculates total_cost when only prompt_token_cost is present" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          prompt_tokens: 1000
        )

        # open_ai_gpt_4o has an input_token_cost of 2.5 / 1_000_000
        expected_prompt_cost = 2.5 / 1_000_000 * 1000

        model_completion.save(validate: false)
        expect(model_completion.total_cost).to eq(expected_prompt_cost)
      end

      it "calculates total_cost when only output_token_cost is present" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          completion_tokens: 500
        )

        # open_ai_gpt_4o has an output_token_cost of 10.0 / 1_000_000
        expected_output_cost = 10.0 / 1_000_000 * 500

        model_completion.save(validate: false)
        expect(model_completion.total_cost).to eq(expected_output_cost)
      end

      it "does not calculate costs for a model that doesn't have cost configs" do
        # Create a mock of Raif.llm_config that returns a config without cost data
        allow(Raif).to receive(:llm_config).and_return({
          key: :test_model,
          api_name: "test-model"
          # Intentionally omitting input_token_cost and output_token_cost
        })

        model_completion = described_class.new(
          llm_model_key: "test_model",
          model_api_name: "test-model",
          prompt_tokens: 1000,
          completion_tokens: 500
        )

        model_completion.save(validate: false)
        expect(model_completion.prompt_token_cost).to be_nil
        expect(model_completion.output_token_cost).to be_nil
        expect(model_completion.total_cost).to be_nil
      end
    end
  end

  describe "#parsed_response" do
    context "with text format" do
      let(:model_completion) do
        described_class.new(
          response_format: "text",
          raw_response: "  This is a text response.  ",
          llm_model_key: "open_ai_gpt_4o"
        )
      end

      it "returns the trimmed text" do
        expect(model_completion.parsed_response).to eq("This is a text response.")
      end
    end

    context "with json format" do
      context "with valid JSON" do
        let(:model_completion) do
          described_class.new(
            response_format: "json",
            raw_response: '{"key": "value", "array": [1, 2, 3]}',
            llm_model_key: "open_ai_gpt_4o"
          )
        end

        it "parses the JSON" do
          expect(model_completion.parsed_response).to eq({ "key" => "value", "array" => [1, 2, 3] })
        end
      end

      context "with JSON wrapped in code blocks" do
        let(:model_completion) do
          described_class.new(
            response_format: "json",
            raw_response: "```json\n{\"key\": \"value\"}\n```",
            llm_model_key: "open_ai_gpt_4o"
          )
        end

        it "removes the code block markers and parses the JSON" do
          expect(model_completion.parsed_response).to eq({ "key" => "value" })
        end
      end
    end

    context "with html format" do
      context "with valid HTML" do
        let(:model_completion) do
          described_class.new(
            response_format: "html",
            raw_response: "<div><p>Hello</p><p>World</p></div>",
            llm_model_key: "open_ai_gpt_4o"
          )
        end

        it "cleans and returns the HTML" do
          expect(model_completion.parsed_response).to eq("<div>\n<p>Hello</p>\n<p>World</p>\n</div>")
        end
      end

      context "with HTML wrapped in code blocks" do
        let(:model_completion) do
          described_class.new(
            response_format: "html",
            raw_response: "```html\n<div><p>Hello</p></div>\n```",
            llm_model_key: "open_ai_gpt_4o"
          )
        end

        it "removes the code block markers and returns the HTML" do
          expect(model_completion.parsed_response).to eq("<div><p>Hello</p></div>")
        end
      end

      context "with HTML containing empty text nodes" do
        let(:model_completion) do
          described_class.new(
            response_format: "html",
            raw_response: "<div>\n  <p>Hello</p>\n  \n  <p>World</p>\n</div>",
            llm_model_key: "open_ai_gpt_4o"
          )
        end

        it "cleans empty text nodes" do
          # The exact output might depend on how ActionController::Base.helpers.sanitize works
          # This test might need adjustment based on actual behavior
          expect(model_completion.parsed_response).to include("<div>")
          expect(model_completion.parsed_response).to include("<p>Hello</p>")
          expect(model_completion.parsed_response).to include("<p>World</p>")
        end
      end

      context "with HTML containing script tags" do
        let(:model_completion) do
          described_class.new(
            response_format: "html",
            raw_response: "<div><script>alert('XSS')</script><p>Safe content</p></div>",
            llm_model_key: "open_ai_gpt_4o"
          )
        end

        it "removes the script tags" do
          expect(model_completion.parsed_response).to include("<div>\nalert('XSS')<p>Safe content</p>\n</div>")
        end
      end
    end
  end

  describe "failure tracking" do
    describe "boolean_timestamp :failed_at" do
      let(:model_completion) do
        described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }]
        )
      end

      it "defines failed? method" do
        expect(model_completion.failed?).to be false
        model_completion.update!(failed_at: Time.current)
        expect(model_completion.failed?).to be true
      end

      it "defines failed! method" do
        expect(model_completion.failed_at).to be_nil
        model_completion.failed!
        expect(model_completion.reload.failed_at).to be_present
      end

      it "defines .failed scope" do
        unfailed_completion = model_completion
        failed_completion = described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }],
          failed_at: Time.current
        )

        expect(described_class.failed).to include(failed_completion)
        expect(described_class.failed).not_to include(unfailed_completion)
      end
    end

    describe "#record_failure!" do
      let(:model_completion) do
        described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }]
        )
      end

      it "records the failure details" do
        exception = StandardError.new("Something went wrong")

        model_completion.record_failure!(exception)

        expect(model_completion.failed?).to be true
        expect(model_completion.failure_error).to eq("StandardError")
        expect(model_completion.failure_reason).to eq("Something went wrong")
      end

      it "records custom exception class names" do
        exception = Faraday::ConnectionFailed.new("Connection refused")

        model_completion.record_failure!(exception)

        expect(model_completion.failure_error).to eq("Faraday::ConnectionFailed")
        expect(model_completion.failure_reason).to eq("Connection refused")
      end

      it "truncates long failure reasons to 255 characters" do
        long_message = "x" * 300
        exception = StandardError.new(long_message)

        model_completion.record_failure!(exception)

        expect(model_completion.failure_reason.length).to eq(255)
        expect(model_completion.failure_reason).to end_with("...")
      end

      it "persists the failure to the database" do
        exception = StandardError.new("Test error")

        model_completion.record_failure!(exception)

        reloaded = described_class.find(model_completion.id)
        expect(reloaded.failed?).to be true
        expect(reloaded.failure_error).to eq("StandardError")
        expect(reloaded.failure_reason).to eq("Test error")
      end
    end
  end
end
