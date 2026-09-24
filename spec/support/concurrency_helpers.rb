# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Raif
  # Latch helpers for the eval concurrency specs, where "did these actually run at the same
  # time?" is the thing under test and the failure mode of getting it wrong is a hung suite.
  #
  # Evals run concurrently in forked worker processes, which share nothing in memory with the
  # example, so the latch is a directory of marker files.
  class ProcessLatch
    def initialize
      @dir = Dir.mktmpdir("raif-latch")
    end

    # Called from a worker: records that `name` got this far.
    def signal(name, stage: "started")
      FileUtils.touch(File.join(@dir, "#{stage}-#{name}"))
    end

    def signalled(stage: "started")
      Dir.children(@dir).filter_map { |file| file.delete_prefix("#{stage}-") if file.start_with?("#{stage}-") }.sort
    end

    # Waits for `count` signals, failing the example rather than blocking forever if they never
    # arrive.
    def await(count, stage: "started", timeout: 10)
      wait_until(timeout, -> { "timed out waiting for #{count} #{stage} signals (got #{signalled(stage: stage).inspect})" }) do
        signalled(stage: stage).size >= count
      end

      signalled(stage: stage)
    end

    def release!
      FileUtils.touch(File.join(@dir, "released"))
    end

    # Called from a worker: blocks until the example calls #release!.
    def wait_for_release(timeout: 10)
      wait_until(timeout, -> { "timed out waiting for the latch to be released" }) { File.exist?(File.join(@dir, "released")) }
    end

    def clear(stage: "started")
      FileUtils.rm_f(Dir.glob(File.join(@dir, "#{stage}-*")))
    end

    def cleanup
      FileUtils.rm_rf(@dir)
    end

  private

    def wait_until(timeout, message)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      until yield
        raise message.call if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.005
      end
    end
  end

  module ConcurrencyHelpers
    def process_latch
      @process_latch ||= ProcessLatch.new
    end
  end
end

RSpec.configure do |config|
  config.include Raif::ConcurrencyHelpers

  config.after do
    @process_latch&.cleanup
  end
end
