# frozen_string_literal: true

require "rails_helper"
require Raif::Engine.root.join("script/smoke/policy")

RSpec.describe Smoke::Policy do
  def capability_result(status, detail: "detail")
    { status: status, detail: detail }
  end

  def model_result(key, explicit:, **capabilities)
    {
      key: key,
      explicit: explicit,
      capabilities: capabilities.transform_keys(&:to_s).transform_values { |status| capability_result(status) }
    }
  end

  describe ".exit_code" do
    it "passes when an explicitly selected model's capability passes" do
      results = [model_result("anthropic_test_model", explicit: true, completion: :pass)]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(0)
    end

    it "fails when an explicitly selected model's capability fails" do
      results = [model_result("anthropic_test_model", explicit: true, completion: :fail)]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(1)
    end

    it "fails when an explicitly selected model's capability is skipped" do
      results = [model_result("anthropic_test_model", explicit: true, completion: :skip)]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(1)
    end

    it "fails when an explicitly selected model's capability times out" do
      results = [model_result("anthropic_test_model", explicit: true, completion: :timeout)]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(1)
    end

    it "never fails on a :note result" do
      results = [model_result("anthropic_test_model", explicit: true, temperature: :note)]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(0)
    end

    it "fails when an explicitly selected model ran no checks at all (unexecuted required check)" do
      results = [{ key: "anthropic_test_model", explicit: true, capabilities: {} }]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(1)
    end

    it "ignores a non-explicit pattern model's pass" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :pass)]

      expect(described_class.exit_code(results, explicit_keys: [])).to eq(0)
    end

    it "fails on a non-explicit pattern model's fail, even when not strict" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :fail)]

      expect(described_class.exit_code(results, explicit_keys: [])).to eq(1)
    end

    it "tolerates a credential skip on a non-explicit pattern model when not strict" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :skip)]

      expect(described_class.exit_code(results, explicit_keys: [])).to eq(0)
    end

    it "tolerates a non-explicit pattern model's timeout when not strict" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :timeout)]

      expect(described_class.exit_code(results, explicit_keys: [])).to eq(0)
    end

    it "fails on an empty capabilities hash on a non-explicit model, even when not strict (unexecuted required check is never tolerated)" do
      results = [{ key: "bedrock_some_model", explicit: false, capabilities: {} }]

      expect(described_class.exit_code(results, explicit_keys: [])).to eq(1)
    end

    it "fails in strict mode on a non-explicit model's fail" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :fail)]

      expect(described_class.exit_code(results, explicit_keys: [], strict: true)).to eq(1)
    end

    it "fails in strict mode on a non-explicit model's timeout (--strict removes the sweep tolerance)" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :timeout)]

      expect(described_class.exit_code(results, explicit_keys: [], strict: true)).to eq(1)
    end

    it "fails in strict mode on a non-explicit model's skip too (--strict removes the sweep tolerance)" do
      results = [model_result("bedrock_some_model", explicit: false, completion: :skip)]

      expect(described_class.exit_code(results, explicit_keys: [], strict: true)).to eq(1)
    end

    it "passes in strict mode when every model passes" do
      results = [
        model_result("anthropic_test_model", explicit: true, completion: :pass),
        model_result("bedrock_some_model", explicit: false, completion: :pass)
      ]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"], strict: true)).to eq(0)
    end

    it "fails the run when a pattern model fails, even though the explicit selection passes" do
      results = [
        model_result("anthropic_test_model", explicit: true, completion: :pass),
        model_result("bedrock_some_model", explicit: false, completion: :fail)
      ]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(1)
    end

    it "tolerates a pattern model's credential skip alongside a passing explicit selection" do
      results = [
        model_result("anthropic_test_model", explicit: true, completion: :pass),
        model_result("bedrock_some_model", explicit: false, completion: :skip)
      ]

      expect(described_class.exit_code(results, explicit_keys: ["anthropic_test_model"])).to eq(0)
    end

    it "fails when any explicit model among several fails" do
      results = [
        model_result("anthropic_test_model", explicit: true, completion: :pass),
        model_result("open_ai_gpt_test", explicit: true, completion: :fail)
      ]

      expect(described_class.exit_code(results, explicit_keys: %w[anthropic_test_model open_ai_gpt_test])).to eq(1)
    end
  end

  describe ".recordable?" do
    it "is recordable for pass" do
      expect(described_class.recordable?(capability_result(:pass))).to eq(true)
    end

    it "is recordable for fail" do
      expect(described_class.recordable?(capability_result(:fail))).to eq(true)
    end

    it "is recordable for note" do
      expect(described_class.recordable?(capability_result(:note))).to eq(true)
    end

    it "is not recordable for skip, even on an explicitly selected model (skips must not masquerade as verification)" do
      expect(described_class.recordable?(capability_result(:skip), explicit_keys: ["anthropic_test_model"])).to eq(false)
    end

    it "is not recordable for timeout, even on an explicitly selected model" do
      expect(described_class.recordable?(capability_result(:timeout), explicit_keys: ["anthropic_test_model"])).to eq(false)
    end
  end
end
