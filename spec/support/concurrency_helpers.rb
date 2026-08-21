# frozen_string_literal: true

module Raif
  # Latch helpers for the eval concurrency specs, where "did these actually run at the same
  # time?" is the thing under test and the failure mode of getting it wrong is a hung suite.
  module ConcurrencyHelpers
    # Pops `count` items off a queue, failing the example rather than blocking forever if they
    # never arrive.
    def await_queue(queue, count, timeout: 10)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      taken = []

      while taken.size < count
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          raise "timed out waiting for #{count} items on the queue (got #{taken.size}: #{taken.inspect})"
        end

        begin
          taken << queue.pop(true)
        rescue ThreadError
          sleep 0.005
        end
      end

      taken
    end
  end
end

RSpec.configure do |config|
  config.include Raif::ConcurrencyHelpers
end
