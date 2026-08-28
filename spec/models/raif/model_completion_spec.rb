# frozen_string_literal: true

# == Schema Information
#
# Table name: raif_model_completions
#
#  id                             :bigint           not null, primary key
#  available_model_tools          :jsonb            not null
#  cache_creation_input_tokens    :integer
#  cache_read_input_tokens        :integer
#  citations                      :jsonb
#  completed_at                   :datetime
#  completion_tokens              :integer
#  failed_at                      :datetime
#  failure_error                  :string
#  failure_reason                 :text
#  failure_response_body          :text
#  failure_response_status        :integer
#  llm_model_key                  :string           not null
#  max_completion_tokens          :integer
#  messages                       :jsonb            not null
#  model_api_name                 :string           not null
#  output_token_cost              :decimal(10, 6)
#  prompt_token_cost              :decimal(10, 6)
#  prompt_tokens                  :integer
#  raw_response                   :text
#  request_settings               :jsonb            not null
#  response_array                 :jsonb
#  response_finish_reason         :string
#  response_format                :integer          default("text"), not null
#  response_format_parameter      :string
#  response_tool_calls            :jsonb
#  retry_count                    :integer          default(0), not null
#  source_type                    :string
#  started_at                     :datetime
#  stream_response                :boolean          default(FALSE), not null
#  system_prompt                  :text
#  temperature                    :decimal(5, 3)
#  tool_choice                    :string
#  total_cost                     :decimal(10, 6)
#  total_tokens                   :integer
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  batch_custom_id                :string
#  raif_model_completion_batch_id :bigint
#  response_id                    :string
#  source_id                      :bigint
#
# Indexes
#
#  index_raif_model_completions_on_batch_custom_id                 (batch_custom_id)
#  index_raif_model_completions_on_batch_id_and_custom_id          (raif_model_completion_batch_id,batch_custom_id) UNIQUE WHERE (raif_model_completion_batch_id IS NOT NULL)
#  index_raif_model_completions_on_completed_at                    (completed_at)
#  index_raif_model_completions_on_created_at                      (created_at)
#  index_raif_model_completions_on_failed_at                       (failed_at)
#  index_raif_model_completions_on_raif_model_completion_batch_id  (raif_model_completion_batch_id)
#  index_raif_model_completions_on_source                          (source_type,source_id)
#  index_raif_model_completions_on_started_at                      (started_at)
#
# Foreign Keys
#
#  fk_rails_...  (raif_model_completion_batch_id => raif_model_completion_batches.id)
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
    describe "create.raif_model_completion instrumentation" do
      it "publishes the record itself, so a subscriber sees later mutations" do
        published = []
        subscriber = ActiveSupport::Notifications.subscribe("create.raif_model_completion") do |event|
          published << event.payload[:model_completion]
        end

        model_completion = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")
        model_completion.total_tokens = 42

        expect(published.size).to eq(1)
        expect(published.first.total_tokens).to eq(42)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      it "is not published for an update" do
        model_completion = FB.create(:raif_model_completion, llm_model_key: "raif_test_llm", model_api_name: "raif-test-llm")

        published = []
        subscriber = ActiveSupport::Notifications.subscribe("create.raif_model_completion") { published << :published }
        model_completion.update!(total_tokens: 7)

        expect(published).to be_empty
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

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

      it "factors retry_count into prompt_token_cost to reflect actual provider billing" do
        model_completion = described_class.new(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          prompt_tokens: 1000,
          completion_tokens: 500,
          retry_count: 3
        )

        # Each retry resends the same prompt, so input cost is multiplied by total attempts (retry_count + 1)
        expected_prompt_cost = 2.5 / 1_000_000 * 1000 * 4
        expected_output_cost = 10.0 / 1_000_000 * 500
        expected_total_cost = expected_prompt_cost + expected_output_cost

        model_completion.save(validate: false)
        expect(model_completion.prompt_token_cost).to eq(expected_prompt_cost)
        expect(model_completion.output_token_cost).to eq(expected_output_cost)
        expect(model_completion.total_cost).to eq(expected_total_cost)
      end

      context "with cached tokens (provider where prompt_tokens includes cached)" do
        it "applies the cache read discount for OpenAI models" do
          # OpenAI: prompt_tokens includes cached tokens as a subset
          # Cache read multiplier is 0.5x for OpenAI
          model_completion = described_class.new(
            llm_model_key: "open_ai_gpt_4o",
            model_api_name: "gpt-4o",
            prompt_tokens: 1000,
            cache_read_input_tokens: 600
          )

          input_cost = 2.5 / 1_000_000
          # 400 non-cached tokens at full price + 600 cached tokens at 50% price
          expected_cost = (400 * input_cost) + (600 * input_cost * 0.5)

          model_completion.save(validate: false)
          expect(model_completion.prompt_token_cost).to eq(expected_cost)
        end
      end

      context "with cached tokens (provider where prompt_tokens excludes cached)" do
        it "adds cache read and creation costs for Anthropic models" do
          # Anthropic: prompt_tokens does NOT include cached tokens
          # Cache read multiplier is 0.1x, cache creation multiplier is 1.25x
          model_completion = described_class.new(
            llm_model_key: "anthropic_claude_4_5_sonnet",
            model_api_name: "claude-sonnet-4-5",
            prompt_tokens: 400,
            cache_read_input_tokens: 600,
            cache_creation_input_tokens: 200
          )

          input_cost = 3.0 / 1_000_000
          # 400 non-cached at full price + 600 cached reads at 10% + 200 cache writes at 125%
          expected_cost = (400 * input_cost) + (600 * input_cost * 0.1) + (200 * input_cost * 1.25)

          model_completion.save(validate: false)
          expect(model_completion.prompt_token_cost).to eq(expected_cost)
        end
      end

      context "with cached tokens and retries" do
        it "factors retry_count into cache-adjusted prompt_token_cost" do
          model_completion = described_class.new(
            llm_model_key: "open_ai_gpt_4o",
            model_api_name: "gpt-4o",
            prompt_tokens: 1000,
            cache_read_input_tokens: 600,
            retry_count: 1
          )

          input_cost = 2.5 / 1_000_000
          # (400 full + 600 at 50%) * 2 attempts
          expected_cost = ((400 * input_cost) + (600 * input_cost * 0.5)) * 2

          model_completion.save(validate: false)
          expect(model_completion.prompt_token_cost).to eq(expected_cost)
        end
      end

      context "with zero cached tokens" do
        it "calculates costs the same as without caching" do
          model_completion = described_class.new(
            llm_model_key: "open_ai_gpt_4o",
            model_api_name: "gpt-4o",
            prompt_tokens: 1000,
            cache_read_input_tokens: 0
          )

          expected_cost = 2.5 / 1_000_000 * 1000

          model_completion.save(validate: false)
          expect(model_completion.prompt_token_cost).to eq(expected_cost)
        end
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

      describe "batch inference discount" do
        let(:batch) do
          FB.create(
            :raif_model_completion_batch_anthropic,
            llm_model_key: "anthropic_claude_4_5_haiku",
            model_api_name: "claude-haiku-4-5"
          )
        end

        it "halves the per-token costs for a model completion attached to a batch" do
          llm_config = Raif.llm_config(:anthropic_claude_4_5_haiku)
          model_completion = described_class.new(
            llm_model_key: "anthropic_claude_4_5_haiku",
            model_api_name: "claude-haiku-4-5",
            prompt_tokens: 100,
            completion_tokens: 50,
            cache_read_input_tokens: 0,
            cache_creation_input_tokens: 0,
            raif_model_completion_batch: batch
          )

          model_completion.save(validate: false)

          expect(model_completion.prompt_token_cost.to_f).to be_within(1e-9).of((llm_config[:input_token_cost] * 100) * 0.5)
          expect(model_completion.output_token_cost.to_f).to be_within(1e-9).of((llm_config[:output_token_cost] * 50) * 0.5)
          expect(model_completion.total_cost.to_f).to be_within(1e-9).of(
            ((llm_config[:input_token_cost] * 100) + (llm_config[:output_token_cost] * 50)) * 0.5
          )
        end

        it "honors a non-default batch_inference_cost_multiplier override" do
          stub_const(
            "Raif::Llms::AnthropicCustomDiscount",
            Class.new(Raif::Llms::Anthropic) do
              def self.batch_inference_cost_multiplier
                0.4
              end
            end
          )
          llm_config = Raif.llm_config(:anthropic_claude_4_5_haiku).merge(llm_class: Raif::Llms::AnthropicCustomDiscount)
          allow(Raif).to receive(:llm_config).and_return(llm_config)

          model_completion = described_class.new(
            llm_model_key: "anthropic_claude_4_5_haiku",
            model_api_name: "claude-haiku-4-5",
            prompt_tokens: 100,
            completion_tokens: 50,
            cache_read_input_tokens: 0,
            cache_creation_input_tokens: 0,
            raif_model_completion_batch: batch
          )

          model_completion.save(validate: false)

          expect(model_completion.prompt_token_cost.to_f).to be_within(1e-9).of((llm_config[:input_token_cost] * 100) * 0.4)
          expect(model_completion.output_token_cost.to_f).to be_within(1e-9).of((llm_config[:output_token_cost] * 50) * 0.4)
        end

        it "is a no-op when the multiplier is exactly 1.0" do
          llm_config = Raif.llm_config(:anthropic_claude_4_5_haiku)
          allow(Raif::Llms::Anthropic).to receive(:batch_inference_cost_multiplier).and_return(1.0)

          model_completion = described_class.new(
            llm_model_key: "anthropic_claude_4_5_haiku",
            model_api_name: "claude-haiku-4-5",
            prompt_tokens: 100,
            completion_tokens: 50,
            cache_read_input_tokens: 0,
            cache_creation_input_tokens: 0,
            raif_model_completion_batch: batch
          )

          model_completion.save(validate: false)

          # No discount: costs match the synchronous path exactly.
          expect(model_completion.prompt_token_cost.to_f).to be_within(1e-9).of(llm_config[:input_token_cost] * 100)
          expect(model_completion.output_token_cost.to_f).to be_within(1e-9).of(llm_config[:output_token_cost] * 50)
        end

        it "leaves total_cost NULL when no tokens are recorded yet (parity with non-batch completions)" do
          # Mirrors the state of a pending Raif::ModelCompletion built by
          # Raif::Llm#build_pending_model_completion: persisted, attached to
          # the batch, but no tokens or costs yet. total_cost should NOT be
          # coerced from NULL to 0 by apply_batch_inference_discount, otherwise
          # batch completions diverge from non-batch completions on aggregate
          # queries that filter on total_cost IS NULL.
          model_completion = described_class.new(
            llm_model_key: "anthropic_claude_4_5_haiku",
            model_api_name: "claude-haiku-4-5",
            raif_model_completion_batch: batch
          )

          model_completion.save(validate: false)

          expect(model_completion.prompt_token_cost).to be_nil
          expect(model_completion.output_token_cost).to be_nil
          expect(model_completion.total_cost).to be_nil
        end
      end
    end
  end

  describe "#truncated?" do
    Raif::ModelCompletion::TRUNCATED_FINISH_REASONS.each do |reason|
      it "returns true for finish reason #{reason.inspect}" do
        model_completion = described_class.new(response_finish_reason: reason)
        expect(model_completion).to be_truncated
      end
    end

    it "returns false for a normally completed response" do
      model_completion = described_class.new(response_finish_reason: "end_turn")
      expect(model_completion).not_to be_truncated
    end

    it "returns false for a content-filter stop, which is deliberately not treated as truncated" do
      model_completion = described_class.new(response_finish_reason: "content_filter")
      expect(model_completion).not_to be_truncated
    end

    it "returns false when no finish reason was recorded" do
      model_completion = described_class.new(response_finish_reason: nil)
      expect(model_completion).not_to be_truncated
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

  describe "start tracking" do
    describe "boolean_timestamp :started_at" do
      let(:model_completion) do
        described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }]
        )
      end

      it "defines started? method" do
        expect(model_completion.started?).to be false
        model_completion.update!(started_at: Time.current)
        expect(model_completion.started?).to be true
      end

      it "defines started! method" do
        expect(model_completion.started_at).to be_nil
        model_completion.started!
        expect(model_completion.reload.started_at).to be_present
      end

      it "defines .started scope" do
        unstarted_completion = model_completion
        started_completion = described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }],
          started_at: Time.current
        )

        expect(described_class.started).to include(started_completion)
        expect(described_class.started).not_to include(unstarted_completion)
      end
    end
  end

  describe "completion tracking" do
    describe "boolean_timestamp :completed_at" do
      let(:model_completion) do
        described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }]
        )
      end

      it "defines completed? method" do
        expect(model_completion.completed?).to be false
        model_completion.update!(completed_at: Time.current)
        expect(model_completion.completed?).to be true
      end

      it "defines completed! method" do
        expect(model_completion.completed_at).to be_nil
        model_completion.completed!
        expect(model_completion.reload.completed_at).to be_present
      end

      it "defines .completed scope" do
        uncompleted_completion = model_completion
        completed_completion = described_class.create!(
          llm_model_key: "open_ai_gpt_4o",
          model_api_name: "gpt-4o",
          messages: [{ "role" => "user", "content" => "Hello" }],
          completed_at: Time.current
        )

        expect(described_class.completed).to include(completed_completion)
        expect(described_class.completed).not_to include(uncompleted_completion)
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

      context "when the exception is a Faraday::Error with a response" do
        let(:body) { '{"error":{"message":"Invalid request: input tokens exceed max"}}' }
        let(:exception) do
          Faraday::BadRequestError.new(
            "the server responded with status 400",
            { status: 400, headers: {}, body: body }
          )
        end

        it "stores the response status and body" do
          model_completion.record_failure!(exception)

          expect(model_completion.failure_error).to eq("Faraday::BadRequestError")
          expect(model_completion.failure_response_status).to eq(400)
          expect(model_completion.failure_response_body).to eq(body)
        end

        it "truncates a body longer than FAILURE_RESPONSE_BODY_MAX_CHARS" do
          long_body = "x" * (described_class::FAILURE_RESPONSE_BODY_MAX_CHARS + 1_000)
          exception = Faraday::BadRequestError.new(
            "the server responded with status 400",
            { status: 400, headers: {}, body: long_body }
          )

          model_completion.record_failure!(exception)

          expect(model_completion.failure_response_body.length).to eq(described_class::FAILURE_RESPONSE_BODY_MAX_CHARS)
        end
      end

      context "when the exception is a Faraday::Error with no response (e.g. ConnectionFailed)" do
        it "leaves failure_response_status and failure_response_body nil" do
          exception = Faraday::ConnectionFailed.new("Connection refused")

          model_completion.record_failure!(exception)

          expect(model_completion.failure_error).to eq("Faraday::ConnectionFailed")
          expect(model_completion.failure_response_status).to be_nil
          expect(model_completion.failure_response_body).to be_nil
        end
      end

      context "when the exception is not a Faraday::Error" do
        it "leaves failure_response_status and failure_response_body nil" do
          model_completion.record_failure!(StandardError.new("kaboom"))

          expect(model_completion.failure_response_status).to be_nil
          expect(model_completion.failure_response_body).to be_nil
        end
      end

      context "when called twice with different exception kinds" do
        it "clears stale response metadata from a prior Faraday failure" do
          first = Faraday::BadRequestError.new(
            "the server responded with status 400",
            { status: 400, headers: {}, body: '{"error":"first"}' }
          )
          model_completion.record_failure!(first)
          expect(model_completion.failure_response_status).to eq(400)
          expect(model_completion.failure_response_body).to eq('{"error":"first"}')

          model_completion.record_failure!(StandardError.new("subsequent failure"))

          expect(model_completion.failure_error).to eq("StandardError")
          expect(model_completion.failure_response_status).to be_nil
          expect(model_completion.failure_response_body).to be_nil
        end
      end
    end
  end

  describe "request_settings" do
    let(:model_completion) { FB.build(:raif_model_completion) }

    it "starts empty, so every setting defers to Raif.config" do
      expect(model_completion.request_settings).to eq({})
      expect(model_completion.open_ai_store_responses).to be(false)
      expect(model_completion.open_router_data_collection).to eq("deny")
      expect(model_completion.open_router_zdr).to be(false)
    end

    it "records only a setting a caller actually set" do
      model_completion.open_ai_store_responses = true

      expect(model_completion.request_settings).to eq({ "open_ai_store_responses" => true })
    end

    it "treats false as a setting rather than as unset" do
      allow(Raif.config).to receive(:open_ai_store_responses).and_return(true)
      model_completion.open_ai_store_responses = false

      expect(model_completion.request_settings).to eq({ "open_ai_store_responses" => false })
      expect(model_completion.open_ai_store_responses).to be(false)
    end

    it "clears a setting back to the config default when assigned nil" do
      model_completion.open_ai_store_responses = true
      model_completion.open_ai_store_responses = nil

      expect(model_completion.request_settings).to eq({})
      expect(model_completion.open_ai_store_responses).to be(false)
    end

    it "stores open_router_data_collection as a string" do
      model_completion.open_router_data_collection = :allow

      expect(model_completion.request_settings).to eq({ "open_router_data_collection" => "allow" })
      expect(model_completion.open_router_data_collection).to eq("allow")
    end

    it "records open_router_zdr" do
      model_completion.open_router_zdr = true

      expect(model_completion.request_settings).to eq({ "open_router_zdr" => true })
      expect(model_completion.open_router_zdr).to be(true)
    end

    it "rejects a key that is not declared in REQUEST_SETTING_KEYS" do
      model_completion.request_settings = { "store_everything" => true }

      expect(model_completion).not_to be_valid
      expect(model_completion.errors[:request_settings].join).to include("undeclared key: store_everything")
    end

    it "rejects a non-boolean open_ai_store_responses" do
      model_completion.request_settings = { "open_ai_store_responses" => "yes" }

      expect(model_completion).not_to be_valid
      expect(model_completion.errors[:request_settings].join).to include("must be true or false")
    end

    it "rejects a non-boolean open_router_zdr" do
      model_completion.request_settings = { "open_router_zdr" => "yes" }

      expect(model_completion).not_to be_valid
      expect(model_completion.errors[:request_settings].join).to include("open_router_zdr must be true or false")
    end

    it "rejects an open_router_data_collection outside allow/deny" do
      model_completion.request_settings = { "open_router_data_collection" => "sometimes" }

      expect(model_completion).not_to be_valid
      expect(model_completion.errors[:request_settings].join).to include("must be one of: allow, deny")
    end
  end

  describe "#provider_managed_tool_calls" do
    it "extracts anthropic-style provider-managed web search details" do
      model_completion = described_class.new(
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch],
        response_array: [
          {
            "type" => "server_tool_use",
            "id" => "srvtoolu_123",
            "name" => "web_search",
            "input" => { "query" => "latest ruby on rails releases" }
          },
          {
            "type" => "web_search_tool_result",
            "tool_use_id" => "srvtoolu_123",
            "content" => [
              {
                "type" => "web_search_result",
                "title" => "Ruby on Rails",
                "url" => "https://rubyonrails.org/?utm_source=test",
                "page_age" => "1 day ago"
              }
            ]
          }
        ],
        citations: [
          {
            "title" => "Ruby on Rails",
            "url" => "https://rubyonrails.org/?utm_source=test"
          }
        ]
      )

      expect(model_completion.provider_managed_tool_calls).to eq([
        {
          "tool_name" => "web_search",
          "provider_tool_call_id" => "srvtoolu_123",
          "status" => nil,
          "arguments" => { "query" => "latest ruby on rails releases" },
          "sources" => [
            {
              "title" => "Ruby on Rails",
              "url" => "https://rubyonrails.org/",
              "page_age" => "1 day ago"
            }
          ],
          "raw_result" => [
            {
              "type" => "web_search_tool_result",
              "tool_use_id" => "srvtoolu_123",
              "content" => [
                {
                  "type" => "web_search_result",
                  "title" => "Ruby on Rails",
                  "url" => "https://rubyonrails.org/?utm_source=test",
                  "page_age" => "1 day ago"
                }
              ]
            }
          ],
          "inferred" => false
        }
      ])
    end

    it "extracts openai-style provider-managed web search details" do
      model_completion = described_class.new(
        llm_model_key: "open_ai_responses_gpt_4o",
        model_api_name: "gpt-4o",
        available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch],
        response_array: [
          {
            "id" => "ws_123",
            "type" => "web_search_call",
            "status" => "completed"
          }
        ],
        citations: [
          {
            "title" => "Ruby on Rails News",
            "url" => "https://rubyonrails.org/blog/?utm_source=openai"
          }
        ]
      )

      expect(model_completion.provider_managed_tool_calls).to eq([
        {
          "tool_name" => "web_search",
          "provider_tool_call_id" => "ws_123",
          "status" => "completed",
          "arguments" => nil,
          "sources" => [
            {
              "title" => "Ruby on Rails News",
              "url" => "https://rubyonrails.org/blog/"
            }
          ],
          "raw_result" => nil,
          "inferred" => false
        }
      ])
    end

    it "infers google web search usage from citations when no explicit tool block is stored" do
      model_completion = described_class.new(
        llm_model_key: "google_gemini_2_5_flash",
        model_api_name: "gemini-2.5-flash",
        available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch],
        response_array: [{ "text" => "Rails 8.1 was recently released." }],
        citations: [
          {
            "title" => "wikipedia.org",
            "url" => "https://en.wikipedia.org/wiki/Ruby_on_Rails"
          }
        ]
      )

      expect(model_completion.provider_managed_tool_calls).to eq([
        {
          "tool_name" => "web_search",
          "provider_tool_call_id" => nil,
          "status" => "completed",
          "arguments" => nil,
          "sources" => [
            {
              "title" => "wikipedia.org",
              "url" => "https://en.wikipedia.org/wiki/Ruby_on_Rails"
            }
          ],
          "raw_result" => nil,
          "inferred" => true
        }
      ])
    end
  end

  describe "#tool_call_summary" do
    it "summarizes developer-managed tool calls with repeat counts" do
      model_completion = described_class.new(
        llm_model_key: "open_ai_gpt_4o",
        model_api_name: "gpt-4o",
        response_tool_calls: [
          { "name" => "google_search_tool" },
          { "name" => "google_search_tool" },
          { "name" => "google_news_search_tool" }
        ]
      )

      expect(model_completion.tool_call_summary).to eq("3: google_search_tool (2), google_news_search_tool")
    end

    it "includes provider-managed tool calls alongside developer-managed ones" do
      model_completion = described_class.new(
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        available_model_tools: [Raif::ModelTools::ProviderManaged::WebSearch],
        response_tool_calls: [{ "name" => "google_search_tool" }],
        response_array: [
          { "type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => { "query" => "rails" } }
        ]
      )

      expect(model_completion.tool_call_summary).to eq("2: google_search_tool, web_search")
    end

    it "returns nil when the completion made no tool calls" do
      model_completion = described_class.new(llm_model_key: "open_ai_gpt_4o", model_api_name: "gpt-4o")

      expect(model_completion.tool_call_summary).to be_nil
    end
  end

  describe "inference cost event sync" do
    let(:task) { FB.create(:raif_test_task) }

    let(:model_completion) do
      FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        source: task,
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150
      )
    end

    it "creates exactly one event with copied values when the completion completes" do
      expect do
        model_completion.completed!
      end.to change(Raif::InferenceCostEvent, :count).by(1)

      event = model_completion.raif_inference_cost_event
      expect(event.original_model_completion_id).to eq(model_completion.id)
      expect(event.source).to eq(task)
      expect(event.source_type).to eq("Raif::Task")
      expect(event.source_class_name).to eq("Raif::TestTask")
      expect(event.llm_model_key).to eq("raif_test_llm")
      expect(event.model_api_name).to eq("raif-test-llm")
      expect(event.prompt_tokens).to eq(100)
      expect(event.completion_tokens).to eq(50)
      expect(event.total_tokens).to eq(150)
      expect(event.prompt_token_cost).to eq(model_completion.prompt_token_cost)
      expect(event.output_token_cost).to eq(model_completion.output_token_cost)
      expect(event.total_cost).to eq(model_completion.total_cost)
      expect(event.retry_count).to eq(model_completion.retry_count)
      expect(event.incurred_at).to eq(model_completion.created_at)
      expect(event.completion_completed_at).to eq(model_completion.completed_at)
      expect(event.completion_failed_at).to be_nil
    end

    it "creates an event when the completion fails via record_failure!" do
      expect do
        model_completion.record_failure!(StandardError.new("provider exploded"))
      end.to change(Raif::InferenceCostEvent, :count).by(1)

      event = model_completion.raif_inference_cost_event
      expect(event.completion_failed_at).to eq(model_completion.failed_at)
      expect(event.completion_completed_at).to be_nil
    end

    it "does not duplicate the event on repeated post-terminal saves and re-syncs copied columns" do
      model_completion.completed!
      event = model_completion.raif_inference_cost_event

      expect do
        model_completion.update!(prompt_tokens: 999, total_tokens: nil)
      end.not_to change(Raif::InferenceCostEvent, :count)

      expect(event.reload.prompt_tokens).to eq(999)
    end

    it "does not re-sync on post-terminal saves that touch no copied column" do
      model_completion.completed!
      event = model_completion.raif_inference_cost_event

      expect do
        model_completion.update!(raw_response: "updated response")
      end.not_to change { event.reload.updated_at }
    end

    it "creates nothing for non-terminal saves (e.g. streaming mid-flight updates)" do
      expect do
        model_completion.update!(raw_response: "partial chunk", prompt_tokens: 10)
      end.not_to change(Raif::InferenceCostEvent, :count)
    end

    it "carries batch-discounted costs on the event" do
      batch = FB.create(
        :raif_model_completion_batch_anthropic,
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5"
      )

      batch_completion = described_class.new(
        llm_model_key: "anthropic_claude_4_5_haiku",
        model_api_name: "claude-haiku-4-5",
        prompt_tokens: 100,
        completion_tokens: 50,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
        raif_model_completion_batch: batch,
        completed_at: Time.current
      )
      batch_completion.save(validate: false)

      event = batch_completion.raif_inference_cost_event
      expect(event).to be_present
      expect(event.raif_model_completion_batch_id).to eq(batch.id)
      # calculate_costs runs before_save (including the batch discount), so the
      # event carries the discounted values.
      expect(event.prompt_token_cost).to eq(batch_completion.prompt_token_cost)
      expect(event.output_token_cost).to eq(batch_completion.output_token_cost)
      expect(event.total_cost).to eq(batch_completion.total_cost)
    end

    it "creates nothing when inference_cost_events_enabled is false" do
      allow(Raif.config).to receive(:inference_cost_events_enabled).and_return(false)

      expect do
        model_completion.completed!
      end.not_to change(Raif::InferenceCostEvent, :count)
    end

    it "merges the configured metadata resolver's output into the event metadata" do
      allow(Raif.config).to receive(:inference_cost_event_metadata).and_return(
        ->(model_completion:) { { "account_id" => 42, "source_id" => model_completion.source_id } }
      )

      model_completion.completed!

      event = model_completion.raif_inference_cost_event
      expect(event.metadata).to eq({ "account_id" => 42, "source_id" => task.id })
    end

    it "falls back to source_type for source_class_name when the source is gone" do
      model_completion.update_columns(source_id: task.id + 1_000_000)

      model_completion.completed!

      event = model_completion.raif_inference_cost_event
      expect(event.source_class_name).to eq("Raif::Task")
    end

    it "re-syncs the event when a copied identity column changes post-terminal" do
      model_completion.completed!
      event = model_completion.raif_inference_cost_event

      model_completion.update!(model_api_name: "raif-test-llm-updated")

      expect(event.reload.model_api_name).to eq("raif-test-llm-updated")
    end

    it "creates a detached event when the completion is terminalized and destroyed in the same transaction" do
      completion_id = model_completion.id

      expect do
        ActiveRecord::Base.transaction do
          model_completion.completed!
          model_completion.destroy!
        end
      end.to change(Raif::InferenceCostEvent, :count).by(1)

      event = Raif::InferenceCostEvent.find_by(original_model_completion_id: completion_id)
      expect(event.raif_model_completion_id).to be_nil
      expect(event.completion_completed_at).to be_present
      expect(event.prompt_tokens).to eq(100)
      expect(event.source_class_name).to eq("Raif::TestTask")
    end

    it "aborts the destroy when a terminal completion's missing event cannot be persisted" do
      allow_any_instance_of(Raif::InferenceCostEvent).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, "boom")

      model_completion.completed!
      expect(model_completion.reload.raif_inference_cost_event).to be_nil

      expect { model_completion.destroy! }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Raif::ModelCompletion.exists?(model_completion.id)).to eq(true)
    end

    it "persists the missing event during destroy when an earlier live sync failed" do
      original_save = Raif::InferenceCostEvent.instance_method(:save!)
      fail_once = true
      allow_any_instance_of(Raif::InferenceCostEvent).to receive(:save!) do |event, **args|
        if fail_once
          fail_once = false
          raise ActiveRecord::StatementInvalid, "transient failure"
        end

        original_save.bind_call(event, **args)
      end

      model_completion.completed!
      expect(model_completion.reload.raif_inference_cost_event).to be_nil

      expect { model_completion.destroy! }.to change(Raif::InferenceCostEvent, :count).by(1)

      event = Raif::InferenceCostEvent.find_by(original_model_completion_id: model_completion.id)
      expect(event.raif_model_completion_id).to be_nil
      expect(event.completion_completed_at).to be_present
    end

    it "updates the existing event without duplicating when a terminal completion is modified and destroyed in one transaction" do
      model_completion.completed!
      event = model_completion.raif_inference_cost_event

      expect do
        ActiveRecord::Base.transaction do
          model_completion.update!(prompt_tokens: 999, total_tokens: nil)
          model_completion.destroy!
        end
      end.not_to change(Raif::InferenceCostEvent, :count)

      event.reload
      expect(event.raif_model_completion_id).to be_nil
      expect(event.prompt_tokens).to eq(999)
    end

    describe "sync failure handling" do
      it "never fails the completion save: reports the error and enqueues the repair job" do
        allow_any_instance_of(Raif::InferenceCostEvent).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, "boom")
        expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::StatementInvalid), handled: true, severity: :error)

        expect do
          model_completion.completed!
        end.to have_enqueued_job(Raif::RepairInferenceCostEventsJob)

        expect(model_completion.reload.completed?).to eq(true)
        expect(model_completion.raif_inference_cost_event).to be_nil
      end

      it "never raises out of the after_commit hook, even when enqueueing the repair job fails" do
        allow_any_instance_of(Raif::InferenceCostEvent).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, "boom")
        allow(Raif::RepairInferenceCostEventsJob).to receive(:perform_later).and_raise(StandardError, "queue backend down")

        expect { model_completion.completed! }.not_to raise_error
        expect(model_completion.reload.completed?).to eq(true)
      end

      it "retries once onto the concurrent writer's row when the unique index is hit" do
        # Simulate losing the insert race: another process created the event
        # between our miss on the association read and our insert.
        concurrent_event = nil
        original_save = Raif::InferenceCostEvent.instance_method(:save!)
        already_raised = false

        allow_any_instance_of(Raif::InferenceCostEvent).to receive(:save!) do |event, **args|
          if event.new_record? && !already_raised
            already_raised = true
            concurrent_event = FB.create(
              :raif_inference_cost_event,
              raif_model_completion_id: model_completion.id,
              original_model_completion_id: model_completion.id,
              prompt_tokens: nil,
              completion_tokens: nil,
              total_tokens: nil
            )
            raise ActiveRecord::RecordNotUnique, "duplicate key"
          else
            original_save.bind_call(event, **args)
          end
        end

        expect do
          model_completion.completed!
        end.to change(Raif::InferenceCostEvent, :count).by(1)

        expect(concurrent_event.reload.prompt_tokens).to eq(100)
        expect(concurrent_event.completion_completed_at).to eq(model_completion.completed_at)
      end
    end

    describe "isolation from the completion's transaction" do
      # Transactional tests would let a genuine PostgreSQL statement error
      # inside the event write poison the example-wrapping transaction, so
      # this group runs without one to prove the production property: the
      # event write happens after commit, where a DB-level failure cannot
      # roll back the already-committed terminal save.
      self.use_transactional_tests = false

      after do
        Raif::InferenceCostEvent.delete_all
        Raif::ModelCompletion.delete_all
      end

      it "commits the terminal save even when the event write fails at the database level" do
        completion = FB.create(
          :raif_model_completion,
          llm_model_key: "raif_test_llm",
          model_api_name: "raif-test-llm"
        )

        allow_any_instance_of(Raif::InferenceCostEvent).to receive(:save!) do
          ActiveRecord::Base.connection.execute("SELECT 1/0")
        end

        expect { completion.completed! }.not_to raise_error

        expect(Raif::ModelCompletion.where(id: completion.id).pick(:completed_at)).to be_present
        expect(Raif::InferenceCostEvent.where(original_model_completion_id: completion.id)).to be_empty
      end
    end
  end
end
