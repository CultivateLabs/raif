# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::WorkerPool do
  def run_pool(pool, items, work:, **options)
    collected = []
    pool.run(items, work: work, collect: ->(item, value) { collected << [item, value] }, **options)
    collected
  end

  it "runs the work in worker processes and collects every value in this one" do
    collected = run_pool(described_class.new(concurrency: 3), (1..9).to_a, work: ->(item) { [item * 2, Process.pid] })

    expect(collected.map(&:first).sort).to eq((1..9).to_a)
    expect(collected.map { |item, (doubled, _pid)| doubled - (item * 2) }.uniq).to eq([0])

    worker_pids = collected.map { |_item, (_doubled, pid)| pid }.uniq
    expect(worker_pids).not_to include(Process.pid)
    expect(worker_pids.size).to be <= 3
  end

  it "runs every item exactly once" do
    latch = process_latch

    run_pool(described_class.new(concurrency: 4), (1..25).to_a, work: ->(item) { latch.signal(item) })

    expect(latch.signalled.map(&:to_i).sort).to eq((1..25).to_a)
  end

  # The point of the whole feature: the waiting has to actually overlap. Each item blocks on a
  # latch that is only released once as many items as the concurrency are simultaneously
  # waiting on it, which cannot happen unless they are genuinely in flight together.
  it "keeps `concurrency` items in flight at once" do
    latch = process_latch
    pool = described_class.new(concurrency: 3)

    thread = Thread.new do
      run_pool(pool, [1, 2, 3, 4, 5], work: lambda do |item|
        latch.signal(item)
        latch.wait_for_release
        item
      end)
    end

    expect(latch.await(3)).to eq(["1", "2", "3"])
    # The fourth has not started: it is waiting for one of the three to give up its worker.
    sleep 0.1
    expect(latch.signalled.size).to eq(3)

    latch.release!
    expect(thread.value.map(&:first).sort).to eq([1, 2, 3, 4, 5])
  end

  it "never exceeds `concurrency`, however many items it is given" do
    collected = run_pool(described_class.new(concurrency: 3), (1..30).to_a, work: lambda do |_item|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep 0.01
      [started, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
    end)

    intervals = collected.map(&:last)
    peak = intervals.map { |started, _| intervals.count { |other_start, other_end| other_start <= started && started < other_end } }.max

    expect(peak).to eq(3)
  end

  it "reports each item to `dispatched` in this process as a worker takes it" do
    dispatched = []

    run_pool(described_class.new(concurrency: 2), [:a, :b, :c], work: ->(item) { item }, dispatched: ->(item) { dispatched << item })

    expect(dispatched).to eq([:a, :b, :c])
  end

  it "sets up each worker with its number before it takes any work" do
    pool = described_class.new(concurrency: 2, setup_worker: ->(number) { ENV["RAIF_SPEC_WORKER_NUMBER"] = number.to_s })

    collected = run_pool(pool, (1..6).to_a, work: lambda do |_item|
      sleep 0.01
      ENV.fetch("RAIF_SPEC_WORKER_NUMBER", nil)
    end)

    expect(collected.map(&:last).uniq.sort).to eq(["1", "2"])
    expect(ENV).not_to have_key("RAIF_SPEC_WORKER_NUMBER")
  end

  it "runs a lone item in a set-up worker too, so it gets the same database as any other" do
    pool = described_class.new(concurrency: 3, setup_worker: ->(number) { ENV["RAIF_SPEC_WORKER_NUMBER"] = number.to_s })

    collected = run_pool(pool, [:a], work: ->(_item) { [ENV.fetch("RAIF_SPEC_WORKER_NUMBER", nil), Process.pid] })

    worker_number, pid = collected.first.last
    expect(worker_number).to eq("1")
    expect(pid).not_to eq(Process.pid)
  end

  describe "at concurrency 1" do
    it "runs the items in order in this process" do
      collected = run_pool(described_class.new(concurrency: 1), [:a, :b, :c], work: ->(item) { [item, Process.pid] })

      expect(collected.map(&:first)).to eq([:a, :b, :c])
      expect(collected.map { |_item, (_value, pid)| pid }.uniq).to eq([Process.pid])
    end
  end

  describe "when an item raises" do
    it "re-raises the failure to the caller, naming the original exception" do
      pool = described_class.new(concurrency: 2)

      expect do
        run_pool(pool, [1, 2, 3, 4, 5, 6], work: lambda do |item|
          raise "item #{item} failed" if item == 1

          item
        end)
      end.to raise_error(Raif::Evals::WorkerPool::WorkerError, "RuntimeError: item 1 failed")
    end

    it "stops taking new items but collects the ones in flight" do
      pool = described_class.new(concurrency: 2)
      collected = []

      expect do
        pool.run((1..20).to_a, collect: ->(item, _value) { collected << item }, work: lambda do |item|
          raise "boom" if item == 2

          sleep 0.2
          item
        end)
      end.to raise_error(Raif::Evals::WorkerPool::WorkerError, "RuntimeError: boom")

      expect(collected).to eq([1])
    end

    it "reports a value that cannot cross the process boundary" do
      pool = described_class.new(concurrency: 2)

      expect do
        run_pool(pool, [1, 2], work: ->(_item) { -> { :not_marshalable } })
      end.to raise_error(Raif::Evals::WorkerPool::WorkerError, /TypeError/)
    end
  end

  it "reports a worker that raises while it is set up, before it takes any work" do
    pool = described_class.new(concurrency: 2, setup_worker: ->(number) { raise "could not create database #{number}" if number == 2 })

    expect do
      run_pool(pool, [1, 2, 3], work: ->(item) { item })
    end.to raise_error(Raif::Evals::WorkerPool::WorkerError, "RuntimeError: could not create database 2")
  end

  it "treats a message truncated by a worker that died mid-write as the worker dying" do
    reader, writer = IO.pipe.each(&:binmode)
    writer.write(Marshal.dump({ type: :result, value: "x" * 1000 })[0, 500])
    writer.close
    dispatch = described_class::Dispatch.new(items: [], work: nil, collect: nil, dispatched: nil, setup_worker: nil)

    expect(dispatch.send(:receive, described_class::Dispatch::Worker.new(results: reader))).to be_nil
  ensure
    reader&.close
  end

  it "reports a worker that dies mid-item" do
    pool = described_class.new(concurrency: 2)

    expect do
      run_pool(pool, [1, 2], work: lambda do |item|
        Process.exit!(false) if item == 1

        item
      end)
    end.to raise_error(Raif::Evals::WorkerPool::WorkerError, /exited while running an execution/)
  end

  # Ctrl-C during an eval run: the in-flight executions have already been paid for, so they are
  # finished and recorded rather than killed. Only the items not yet started are dropped.
  describe "when interrupted" do
    it "finishes the in-flight items, drops the rest, and re-raises" do
      latch = process_latch
      pool = described_class.new(concurrency: 2)
      collected = Queue.new

      runner = Thread.new do
        # The Interrupt below is the assertion, not a crash to report to stderr.
        Thread.current.report_on_exception = false

        pool.run((1..10).to_a, collect: ->(item, _value) { collected << item }, work: lambda do |item|
          latch.signal(item)
          latch.wait_for_release
          item
        end)
      end

      latch.await(2)
      runner.raise(Interrupt)
      latch.release!

      expect { runner.join }.to raise_error(Interrupt)
      expect(collected.size).to eq(2)
      expect(latch.signalled.size).to eq(2)
    end

    it "treats an Interrupt raised inside the work the same way" do
      latch = process_latch
      pool = described_class.new(concurrency: 2)
      collected = []

      expect do
        pool.run([1, 2, 3, 4], collect: ->(item, _value) { collected << item }, work: lambda do |item|
          raise Interrupt if item == 1

          latch.signal(item)
          sleep 0.2
          item
        end)
      end.to raise_error(Interrupt)

      expect(collected).to eq([2])
      expect(latch.signalled).to eq(["2"])
    end
  end
end
