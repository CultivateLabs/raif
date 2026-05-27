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

  # @param label [String] short identifier for log lines (e.g. "open_ai
  #   submit_batch upload"). Surfaces in retry/exhaustion log messages so the
  #   call site is visible without grepping.
  # @param max_retries [Integer] retries permitted after the initial attempt.
  #   Defaults to Raif.config.llm_request_max_retries.
  # @param retriable_exceptions [Array<Class>] exception classes that trigger
  #   a retry. Anything else raises immediately. Defaults to
  #   Raif.config.llm_request_retriable_exceptions.
  # @param base_delay [Numeric] seconds for the first backoff interval.
  # @param max_delay [Numeric] cap for the exponential backoff in seconds.
  # @param on_retry [Proc, nil] optional callback invoked before each sleep
  #   with (error, attempt, max_retries, delay). Use this to layer call-site
  #   bookkeeping on top of the default logging (e.g. incrementing a counter).
  # @yield the block to execute. Re-yielded on each retry.
  # @return whatever the block returns on its successful attempt.
  # @raise the original exception once retries are exhausted, or immediately
  #   for non-retriable exceptions.
  def self.call(label:, max_retries: nil, retriable_exceptions: nil, base_delay: DEFAULT_BASE_DELAY, max_delay: DEFAULT_MAX_DELAY, on_retry: nil)
    max_retries ||= Raif.config.llm_request_max_retries
    retriable_exceptions ||= Raif.config.llm_request_retriable_exceptions
    retriable_exceptions = Array(retriable_exceptions)

    attempt = 0
    begin
      yield
    rescue *retriable_exceptions => e
      attempt += 1
      if attempt <= max_retries
        delay = [base_delay * (2**(attempt - 1)), max_delay].min
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

  # Indirection so tests can stub the sleep without monkey-patching Kernel.
  # Stub via `allow(Raif::Utils::TransientRetry).to receive(:sleep_for)`.
  def self.sleep_for(seconds)
    sleep(seconds)
  end
  private_class_method :sleep_for
end
