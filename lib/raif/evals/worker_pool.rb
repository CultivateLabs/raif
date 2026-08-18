# frozen_string_literal: true

module Raif
  module Evals
    # Runs a list of work items across a bounded pool of threads.
    #
    # An eval run is almost entirely waiting on provider HTTP responses, so overlapping the
    # waiting is where the wall clock goes. Threads rather than fibers: Net::HTTP only yields to
    # a fiber scheduler, and Raif's inference path is stateless per call (Raif.llm builds a
    # fresh client per call, and nothing in Raif keeps per-thread state).
    class WorkerPool
      attr_reader :concurrency

      def initialize(concurrency: 1)
        @concurrency = [concurrency.to_i, 1].max
      end

      # Runs the block once per item and returns its values in item order, whatever order the
      # items actually completed in.
      #
      # On Ctrl-C, workers stop before taking their next item and the in-flight ones are joined
      # rather than killed, so their results still reach whatever the caller records them in.
      # The Interrupt is then re-raised for the caller to report on.
      def run(items, &block)
        # Not just an optimization: a serial run stays on the main thread, with no executor
        # wrapping and no second connection.
        return items.map(&block) if concurrency == 1 || items.size <= 1

        state = State.new(items: items)
        workers = [concurrency, items.size].min.times.map { start_worker(state, &block) }

        begin
          workers.each(&:join)
        rescue Interrupt
          state.stop!
          workers.each(&:join)
          raise
        end

        raise state.failure if state.failure

        state.results
      end

    private

      def start_worker(state, &block)
        Thread.new do
          # The pool reports failures through State; the default handler would also dump the
          # backtrace to stderr, interleaved into the run's output.
          Thread.current.report_on_exception = false

          while (index = state.take)
            in_worker_context { state.results[index] = block.call(state.items[index]) }
          end
        rescue StandardError, Interrupt => e
          state.fail!(e)
        end
      end

      # executor.wrap gives each item the same boundary a Rails request gets: it is what makes
      # concurrent Zeitwerk autoloads safe, and it returns the connection and clears per-thread
      # state afterwards.
      #
      # It also clears ActiveSupport::IsolatedExecutionState, which is where
      # Raif::Evals::ModelCompletionSink lives, so the sink has to be opened inside this
      # boundary. EvalSet#run_eval opens it, so anything reached from here is fine; hoisting the
      # sink out to the pool would silently stop capturing completions.
      def in_worker_context(&block)
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection_pool.with_connection(&block)
        end
      end

      # The pool's shared mutable state, behind one mutex.
      class State
        attr_reader :items, :results, :failure

        def initialize(items:)
          @items = items
          @results = Array.new(items.size)
          @next_index = 0
          @stopped = false
          @failure = nil
          @mutex = Mutex.new
        end

        # The index of the next item to run, or nil once the list is exhausted or the run is
        # stopping. Deliberately checked between items rather than mid-item: an execution that
        # has already paid for its inference should finish and be recorded.
        def take
          @mutex.synchronize do
            return if @stopped || @next_index >= @items.size

            @next_index.tap { @next_index += 1 }
          end
        end

        def stop!
          @mutex.synchronize { @stopped = true }
        end

        # First failure wins: the ones that follow are usually the same provider outage seen by
        # the other workers.
        def fail!(error)
          @mutex.synchronize do
            @stopped = true
            @failure ||= error
          end
        end
      end
    end
  end
end
