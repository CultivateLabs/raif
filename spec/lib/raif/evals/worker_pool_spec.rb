# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::WorkerPool do
  it "returns results in item order however the items completed" do
    pool = described_class.new(concurrency: 4)

    results = pool.run([0.03, 0.0, 0.02, 0.0]) do |delay|
      sleep delay
      delay
    end

    expect(results).to eq([0.03, 0.0, 0.02, 0.0])
  end

  it "runs every item exactly once" do
    pool = described_class.new(concurrency: 4)
    seen = Queue.new

    pool.run((1..25).to_a) { |item| seen << item }

    expect(Array.new(seen.size) { seen.pop }.sort).to eq((1..25).to_a)
  end

  # The point of the whole feature: the waiting has to actually overlap. Each item blocks on a
  # latch that is only released once as many items as the concurrency are simultaneously
  # waiting on it, which cannot happen unless they are genuinely in flight together.
  it "keeps `concurrency` items in flight at once" do
    pool = described_class.new(concurrency: 3)
    started = Queue.new
    release = Queue.new

    thread = Thread.new do
      pool.run([1, 2, 3, 4, 5]) do |item|
        started << item
        release.pop
        item
      end
    end

    expect(await_queue(started, 3).sort).to eq([1, 2, 3])
    # The fourth has not started: it is waiting for one of the three to give up its slot.
    expect(started).to be_empty

    5.times { release << :go }
    expect(thread.value).to eq([1, 2, 3, 4, 5])
  end

  it "never exceeds `concurrency`, however many items it is given" do
    pool = described_class.new(concurrency: 3)
    mutex = Mutex.new
    in_flight = 0
    peak = 0

    pool.run((1..30).to_a) do
      mutex.synchronize do
        in_flight += 1
        peak = [peak, in_flight].max
      end
      sleep 0.001
      mutex.synchronize { in_flight -= 1 }
    end

    expect(peak).to eq(3)
  end

  describe "at concurrency 1" do
    it "runs the items in order on the calling thread" do
      pool = described_class.new(concurrency: 1)
      order = []
      threads = []

      pool.run([:a, :b, :c]) do |item|
        order << item
        threads << Thread.current
      end

      expect(order).to eq([:a, :b, :c])
      expect(threads.uniq).to eq([Thread.current])
    end
  end

  describe "when an item raises" do
    it "re-raises the failure to the caller once the workers have stopped" do
      pool = described_class.new(concurrency: 2)

      expect do
        pool.run([1, 2, 3, 4, 5, 6]) do |item|
          raise "item #{item} failed" if item == 1

          item
        end
      end.to raise_error(RuntimeError, "item 1 failed")
    end

    it "stops taking new items rather than working through the rest of the list" do
      pool = described_class.new(concurrency: 1)
      seen = []

      expect do
        pool.run((1..20).to_a) do |item|
          seen << item
          raise "boom" if item == 2

          item
        end
      end.to raise_error(RuntimeError, "boom")

      expect(seen).to eq([1, 2])
    end
  end

  # Ctrl-C during an eval run: the in-flight executions have already been paid for, so they are
  # finished and recorded rather than killed. Only the items not yet started are dropped.
  describe "when interrupted" do
    it "finishes the in-flight items, drops the rest, and re-raises" do
      pool = described_class.new(concurrency: 2)
      started = Queue.new
      release = Queue.new
      finished = Queue.new

      runner = Thread.new do
        # The Interrupt below is the assertion, not a crash to report to stderr.
        Thread.current.report_on_exception = false

        pool.run((1..10).to_a) do |item|
          started << item
          release.pop
          finished << item
          item
        end
      end

      await_queue(started, 2)
      runner.raise(Interrupt)
      2.times { release << :go }

      expect { runner.join }.to raise_error(Interrupt)
      expect(finished.size).to eq(2)
      expect(started.size).to be_zero
    end
  end
end
