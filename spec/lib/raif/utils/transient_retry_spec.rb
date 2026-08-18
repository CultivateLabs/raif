# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Utils::TransientRetry do
  # One rate-limited call that succeeds on its retry, returning the delays it slept for.
  def retry_after_delays(header:, options: {})
    delays = []
    attempts = 0

    described_class.call(
      label: "test",
      max_retries: 2,
      retriable_exceptions: [Faraday::TooManyRequestsError],
      on_retry: ->(_e, _attempt, _max, delay) { delays << delay },
      **options
    ) do
      attempts += 1
      raise Faraday::TooManyRequestsError.new(nil, { headers: { "retry-after" => header } }) if attempts < 2

      :ok
    end

    delays
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
        jitter: 0,
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
          jitter: 0,
          on_retry: ->(_e, _attempt, _max, delay) { delays << delay }
        ) do
          attempts += 1
          raise Faraday::ServerError, "boom"
        end
      end.to raise_error(Faraday::ServerError)

      # base_delay=10 capped at max_delay=12: 10, 12, 12, 12
      expect(delays).to eq([10, 12, 12, 12])
    end

    # Concurrent callers rate limited at the same instant would otherwise retry at the same
    # instant, and keep colliding for as many rounds as they have retries.
    it "spreads the delay over a jitter window rather than backing off in lockstep" do
      delays = []
      attempts = 0

      expect do
        described_class.call(
          label: "test",
          max_retries: 30,
          retriable_exceptions: [Faraday::ServerError],
          base_delay: 8,
          max_delay: 8,
          jitter: 0.25,
          on_retry: ->(_e, _attempt, _max, delay) { delays << delay }
        ) do
          attempts += 1
          raise Faraday::ServerError, "boom"
        end
      end.to raise_error(Faraday::ServerError)

      expect(delays.uniq.size).to be > 1
      expect(delays).to all(be_between(6, 8))
    end

    # 429 is the failure concurrency makes routine, and the one where the provider says how long
    # to wait rather than leaving it to be guessed.
    it "waits the Retry-After the provider sent, in place of the exponential delay" do
      delays = retry_after_delays(header: "9", options: { base_delay: 3, jitter: 0 })

      expect(delays).to eq([9])
    end

    # max_delay bounds Raif's guess. The provider's own instruction is not a guess, and coming
    # back at 30s when it said 60 spends a retry to be told 429 again.
    it "honors a Retry-After past max_delay" do
      delays = retry_after_delays(header: "60", options: { max_delay: 30, jitter: 0 })

      expect(delays).to eq([60])
    end

    it "caps Retry-After at MAX_RETRY_AFTER_DELAY, so a provider cannot park the run for an hour" do
      delays = retry_after_delays(header: "3600", options: { jitter: 0 })

      expect(delays).to eq([described_class::MAX_RETRY_AFTER_DELAY])
    end

    # The header is the most likely reason N concurrent callers agree on a delay to the
    # millisecond, so it is the path that most needs jitter - added rather than subtracted,
    # since returning before the provider said to only buys another 429.
    it "jitters the Retry-After delay upward rather than retrying on it in lockstep" do
      delays = 25.times.flat_map { retry_after_delays(header: "8", options: { jitter: 0.25 }) }

      expect(delays.uniq.size).to be > 1
      expect(delays).to all(be_between(8, 10))
    end

    it "falls back to the exponential delay when Retry-After is an HTTP date rather than seconds" do
      delays = []
      attempts = 0

      described_class.call(
        label: "test",
        max_retries: 2,
        retriable_exceptions: [Faraday::TooManyRequestsError],
        base_delay: 5,
        jitter: 0,
        on_retry: ->(_e, _attempt, _max, delay) { delays << delay }
      ) do
        attempts += 1
        raise Faraday::TooManyRequestsError.new(nil, { headers: { "retry-after" => "Wed, 21 Oct 2015 07:28:00 GMT" } }) if
          attempts < 2

        :ok
      end

      expect(delays).to eq([5])
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
