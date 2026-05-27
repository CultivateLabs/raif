# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Utils::TransientRetry do
  before do
    allow(described_class).to receive(:sleep_for) # never actually sleep in tests
  end

  describe ".call" do
    it "returns the block's value on the first attempt when nothing raises" do
      attempts = 0

      result = described_class.call(label: "test") do
        attempts += 1
        :ok
      end

      expect(result).to eq(:ok)
      expect(attempts).to eq(1)
    end

    it "retries a retriable exception then returns the eventual success value" do
      attempts = 0

      result = described_class.call(
        label: "test",
        max_retries: 2,
        retriable_exceptions: [Faraday::ServerError]
      ) do
        attempts += 1
        raise Faraday::ServerError, "boom" if attempts < 2

        :recovered
      end

      expect(result).to eq(:recovered)
      expect(attempts).to eq(2)
    end

    it "raises the original exception once retries are exhausted" do
      attempts = 0

      expect do
        described_class.call(
          label: "test",
          max_retries: 2,
          retriable_exceptions: [Faraday::ServerError]
        ) do
          attempts += 1
          raise Faraday::ServerError, "always fails"
        end
      end.to raise_error(Faraday::ServerError, "always fails")

      # Initial attempt + 2 retries = 3 total attempts
      expect(attempts).to eq(3)
    end

    it "passes non-retriable exceptions through immediately without retrying" do
      attempts = 0

      expect do
        described_class.call(
          label: "test",
          max_retries: 5,
          retriable_exceptions: [Faraday::ServerError]
        ) do
          attempts += 1
          raise ArgumentError, "fatal"
        end
      end.to raise_error(ArgumentError, "fatal")

      expect(attempts).to eq(1)
    end

    it "invokes on_retry with (error, attempt, max_retries, delay) before each sleep" do
      observed = []
      attempts = 0

      described_class.call(
        label: "test",
        max_retries: 2,
        retriable_exceptions: [Faraday::ServerError],
        base_delay: 7,
        max_delay: 30,
        on_retry: ->(error, attempt, max_retries, delay) {
          observed << [error.class, error.message, attempt, max_retries, delay]
        }
      ) do
        attempts += 1
        raise Faraday::ServerError, "blip ##{attempts}" if attempts < 3

        :done
      end

      expect(observed).to eq([
        [Faraday::ServerError, "blip #1", 1, 2, 7],
        [Faraday::ServerError, "blip #2", 2, 2, 14]
      ])
    end

    it "caps the backoff delay at max_delay" do
      delays = []
      attempts = 0

      expect do
        described_class.call(
          label: "test",
          max_retries: 4,
          retriable_exceptions: [Faraday::ServerError],
          base_delay: 10,
          max_delay: 12,
          on_retry: ->(_e, _attempt, _max, delay) { delays << delay }
        ) do
          attempts += 1
          raise Faraday::ServerError, "boom"
        end
      end.to raise_error(Faraday::ServerError)

      # base_delay=10 capped at max_delay=12: 10, 12, 12, 12
      expect(delays).to eq([10, 12, 12, 12])
    end

    it "defaults max_retries and retriable_exceptions to the Raif.config values" do
      allow(Raif.config).to receive(:llm_request_max_retries).and_return(1)
      allow(Raif.config).to receive(:llm_request_retriable_exceptions).and_return([Faraday::TimeoutError])

      attempts = 0
      expect do
        described_class.call(label: "test") do
          attempts += 1
          raise Faraday::TimeoutError
        end
      end.to raise_error(Faraday::TimeoutError)

      # 1 initial + 1 retry = 2 attempts
      expect(attempts).to eq(2)
    end
  end
end
