# frozen_string_literal: true

# Retries a block on transient errors using exponential backoff.
#
# Single source of truth for "retry the HTTP call on a network blip" across
# Raif's synchronous (Raif::Llm#perform_model_completion!) and batch
# (Raif::Concerns::Llms::*::BatchInference) paths.
#
# Defaults to Raif.config.llm_request_max_retries and
# Raif.config.llm_request_retriable_exceptions so retry behavior moves
# together when hosts tune those.
class Raif::Utils::TransientRetry
  DEFAULT_BASE_DELAY = 3
  DEFAULT_MAX_DELAY = 30
  # Fraction of each delay that is randomized away. Without it, N requests rate limited at the
  # same moment retry at the same moment, and keep colliding for as many rounds as they have.
  DEFAULT_JITTER = 0.25
  # Ceiling on a provider-supplied Retry-After. That header is honored past max_delay, which
  # bounds Raif's guess rather than the provider's own instruction - but a provider asking for
  # an hour should not hang a run for one.
  MAX_RETRY_AFTER_DELAY = 300

  # @param label [String] short identifier for log lines (e.g. "open_ai
  #   submit_batch upload"). Surfaces in retry/exhaustion log messages so the
  #   call site is visible without grepping.
  # @param max_retries [Integer] retries permitted after the initial attempt.
  #   Defaults to Raif.config.llm_request_max_retries.
  # @param retriable_exceptions [Array<Class>] exception classes that trigger
  #   a retry. Anything else raises immediately. Defaults to
  #   Raif.config.llm_request_retriable_exceptions.
  # @param base_delay [Numeric] seconds for the first backoff interval.
  # @param max_delay [Numeric] cap for the exponential backoff in seconds. Does
  #   not bound a provider-supplied Retry-After, which MAX_RETRY_AFTER_DELAY does.
  # @param jitter [Float] fraction of each delay to randomize, so concurrent
  #   callers retrying the same outage do not retry in lockstep. Taken off an
  #   exponential delay and added to a Retry-After one. Pass 0 for an exactly
  #   reproducible backoff curve.
  # @param on_retry [Proc, nil] optional callback invoked before each sleep
  #   with (error, attempt, max_retries, delay). Use this to layer call-site
  #   bookkeeping on top of the default logging (e.g. incrementing a counter).
  # @yield the block to execute. Re-yielded on each retry.
  # @return whatever the block returns on its successful attempt.
  # @raise the original exception once retries are exhausted, or immediately
  #   for non-retriable exceptions.
  def self.call(label:, max_retries: nil, retriable_exceptions: nil, base_delay: DEFAULT_BASE_DELAY, max_delay: DEFAULT_MAX_DELAY,
    jitter: DEFAULT_JITTER, on_retry: nil)
    max_retries ||= Raif.config.llm_request_max_retries
    retriable_exceptions ||= Raif.config.llm_request_retriable_exceptions
    retriable_exceptions = Array(retriable_exceptions)

    attempt = 0
    begin
      yield
    rescue *retriable_exceptions => e
      attempt += 1
      if attempt <= max_retries
        delay = delay_for(e, attempt: attempt, base_delay: base_delay, max_delay: max_delay, jitter: jitter)
        on_retry&.call(e, attempt, max_retries, delay)
        Raif.logger.warn(
          "Raif::Utils::TransientRetry[#{label}]: retry #{attempt}/#{max_retries} " \
            "after #{e.class}: #{e.message}. Sleeping #{delay}s."
        )
        sleep_for(delay)
        retry
      end

      Raif.logger.error(
        "Raif::Utils::TransientRetry[#{label}]: exhausted #{max_retries} retries. " \
          "Last error: #{e.class}: #{e.message}"
      )
      raise
    end
  end

  # A Retry-After header, when the provider sent one, is the only number here that is not a
  # guess. Exponential backoff otherwise. Both paths are jittered, the header path especially:
  # a 429 is what produces N callers limited at once, and a header is the most likely reason
  # they would then agree on a delay to the millisecond.
  def self.delay_for(error, attempt:, base_delay:, max_delay:, jitter:)
    retry_after = retry_after_seconds(error)
    return jittered_up([retry_after, MAX_RETRY_AFTER_DELAY].min, jitter) if retry_after

    jittered_down([base_delay * (2**(attempt - 1)), max_delay].min, jitter)
  end
  private_class_method :delay_for

  # The exponential delay is a ceiling - max_delay caps it - so the randomness comes off the top.
  def self.jittered_down(delay, jitter)
    return delay if jitter.to_f.zero?

    (delay - (delay * jitter * rand)).round(3)
  end
  private_class_method :jittered_down

  # Retry-After is a floor, so the randomness goes on top: coming back before the provider said
  # to only buys another 429 and spends a retry to learn nothing.
  def self.jittered_up(delay, jitter)
    return delay if jitter.to_f.zero?

    (delay + (delay * jitter * rand)).round(3)
  end
  private_class_method :jittered_up

  # Seconds only. Retry-After also allows an HTTP date, which no LLM provider sends and which
  # would need a trusted clock to act on.
  def self.retry_after_seconds(error)
    return unless error.respond_to?(:response_headers)

    header = error.response_headers&.find { |key, _value| key.to_s.casecmp?("retry-after") }&.last
    seconds = Integer(header.to_s.strip, exception: false)

    seconds if seconds&.positive?
  end
  private_class_method :retry_after_seconds

  # Indirection so tests can stub the sleep without monkey-patching Kernel.
  # Stub via `allow(Raif::Utils::TransientRetry).to receive(:sleep_for)`.
  def self.sleep_for(seconds)
    sleep(seconds)
  end
  private_class_method :sleep_for
end
