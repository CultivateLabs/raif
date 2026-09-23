# frozen_string_literal: true

module Raif
  module Evals
    # Runs a list of work items across a bounded pool of forked worker processes.
    #
    # An eval run is almost entirely waiting on provider HTTP responses, so overlapping the
    # waiting is where the wall clock goes. Processes rather than threads, because each worker
    # needs a database of its own: every execution runs in a transaction that is rolled back, and
    # two executions sharing a database block on any unique index both of them write the same key
    # to until the first one rolls back. Seeded reference rows and a repeated case do that on every
    # execution, so on one shared database those executions run one at a time.
    #
    # The work runs in a child, and everything that records it runs here in the parent: `work`
    # returns a value that crosses the process boundary with Marshal, and `collect` receives it.
    class WorkerPool
      # A worker raised outside the work it was given, or died. The original exception lives in
      # another process, so this carries its class, message, and backtrace instead.
      class WorkerError < StandardError; end

      attr_reader :concurrency

      # @param setup_worker [#call, nil] called in each child once it has forked, with its
      #   1-based worker number, before it takes any work.
      def initialize(concurrency: 1, setup_worker: nil)
        @concurrency = [concurrency.to_i, 1].max
        @setup_worker = setup_worker
      end

      # Calls `work` once per item in a worker and `collect` with each item and its value in this
      # process, in completion order. `dispatched` is called here with each item as a worker takes
      # it. Both callbacks only ever run on the calling thread, so they need no locking.
      #
      # On Ctrl-C, workers stop taking items and the in-flight ones are waited for rather than
      # killed, so their results still reach `collect`. The Interrupt is then re-raised for the
      # caller to report on. A second Ctrl-C stops waiting and kills the workers.
      def run(items, work:, collect:, dispatched: nil)
        if concurrency == 1 || items.size <= 1
          return items.each do |item|
            dispatched&.call(item)
            collect.call(item, work.call(item))
          end
        end

        Dispatch.new(items: items, work: work, collect: collect, dispatched: dispatched, setup_worker: @setup_worker)
          .run(worker_count: [concurrency, items.size].min)
      end

      # One run's workers and the items still to hand them. Rails discards the connection pools a
      # child inherits on its first use of them, so nothing here has to close the parent's.
      class Dispatch
        Worker = Struct.new(:number, :pid, :tasks, :results, keyword_init: true)

        def initialize(items:, work:, collect:, dispatched:, setup_worker:)
          @items = items
          @work = work
          @collect = collect
          @dispatched = dispatched
          @setup_worker = setup_worker
          @workers = []
          @next_index = 0
          @in_flight = {}
          @stopping = false
          @interrupted = false
          @failure = nil
        end

        def run(worker_count:)
          worker_count.times { |i| @workers << fork_worker(i + 1) }
          @workers.each { |worker| dispatch(worker) }

          drain

          raise Interrupt if @interrupted
          raise @failure if @failure
        ensure
          shut_down
        end

      private

        # First Ctrl-C: stop dispatching and keep collecting. Second: stop waiting.
        def drain
          collect_results until @in_flight.empty?
        rescue Interrupt
          raise if @interrupted

          @interrupted = true
          @stopping = true
          retry
        end

        def collect_results
          ready, = IO.select(@in_flight.keys.map(&:results))

          ready.each do |io|
            worker = @in_flight.keys.find { |candidate| candidate.results == io }
            index = @in_flight.delete(worker)
            handle(worker, index, receive(worker))
          end
        end

        def handle(worker, index, message)
          case message&.fetch(:type)
          when :result
            @collect.call(@items[index], message[:value])
            dispatch(worker)
          when :interrupt
            @interrupted = true
            @stopping = true
          when :error
            fail!(WorkerError.new("#{message[:class]}: #{message[:message]}").tap { |e| e.set_backtrace(message[:backtrace]) })
          else
            fail!(WorkerError.new("eval worker #{worker.number} (pid #{worker.pid}) exited while running an execution"))
          end
        end

        # First failure wins: the ones that follow are usually the same provider outage seen by
        # the other workers.
        def fail!(error)
          @failure ||= error
          @stopping = true
        end

        def dispatch(worker)
          return if @stopping || @next_index >= @items.size

          index = @next_index
          @next_index += 1
          @in_flight[worker] = index
          @dispatched&.call(@items[index])
          write_message(worker.tasks, index)
        end

        def receive(worker)
          Marshal.load(worker.results)
        rescue EOFError, Errno::ECONNRESET
          nil
        end

        def fork_worker(number)
          # Binary, or a host that sets Encoding.default_internal - Rails does - has every message
          # transcoded, and Marshal data is not valid in any text encoding.
          tasks_reader, tasks_writer = IO.pipe.each(&:binmode)
          results_reader, results_writer = IO.pipe.each(&:binmode)
          siblings = @workers.flat_map { |worker| [worker.tasks, worker.results] }

          pid = Process.fork do
            # A sibling's end of its pipes held open here would keep that sibling from ever
            # seeing the end of its task list.
            siblings.each(&:close)
            tasks_writer.close
            results_reader.close
            run_worker(number, tasks_reader, results_writer)
          end

          tasks_reader.close
          results_writer.close
          Worker.new(number: number, pid: pid, tasks: tasks_writer, results: results_reader)
        end

        # Ctrl-C reaches every process in the foreground group. Ignored here so the execution in
        # flight finishes and reaches the parent, which decides when to stop.
        #
        # exit! rather than exit: the child inherited the parent's at_exit hooks, and running them
        # twice would, among other things, report a test suite's results once per worker.
        def run_worker(number, tasks, results)
          trap("INT", "IGNORE")
          @setup_worker&.call(number)

          loop do
            index = begin
              Marshal.load(tasks)
            rescue EOFError
              break
            end

            write_message(results, { type: :result, value: @work.call(@items[index]) })
          end
        rescue Interrupt
          write_message(results, { type: :interrupt })
        rescue Exception => e
          write_message(results, { type: :error, class: e.class.name, message: e.message, backtrace: e.backtrace })
        ensure
          Process.exit!(true)
        end

        # Dumped to a string before any of it is written, so a value Marshal cannot serialize
        # raises here rather than leaving half a message in the pipe for the reader to choke on.
        def write_message(io, message)
          io.write(Marshal.dump(message))
          io.flush
        rescue Errno::EPIPE
          nil
        end

        # Closing a worker's task pipe is its signal to exit once it finishes what it holds. A
        # worker still running after a second Ctrl-C is killed instead.
        def shut_down
          @workers.each do |worker|
            worker.tasks.close unless worker.tasks.closed?
            Process.kill("TERM", worker.pid) if @in_flight.key?(worker)
          rescue Errno::ESRCH
            nil
          end

          @workers.each do |worker|
            Process.wait(worker.pid)
            worker.results.close unless worker.results.closed?
          rescue Errno::ECHILD
            nil
          end
        end
      end
    end
  end
end
