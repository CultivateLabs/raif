# frozen_string_literal: true

module Raif
  module Evals
    # Serializes a run's console output onto one IO.
    #
    # Concurrent evals each produce several lines - a case summary and the failing expectations
    # beneath it, or an error and its backtrace - that only make sense together. Buffered mode
    # collects one execution's lines and emits them as a single block, so two executions
    # finishing at once cannot interleave their lines.
    #
    # Headers (the eval set name, the eval description) are handed to #capture rather than
    # printed up front: under concurrency, results arrive in completion order, so the first
    # moment a header is known to describe the lines beneath it is when the first of those lines
    # is ready to print.
    class ConsoleWriter
      # @param output [IO] where lines are ultimately written.
      # @param buffered [Boolean] when false, blocks write straight through to output. A serial
      #   run has nothing to interleave with, and writing through keeps a slow eval's output
      #   appearing as it happens rather than only once the eval finishes.
      def initialize(output, buffered: false)
        @output = output
        @buffered = buffered
        @mutex = Mutex.new
        @printed_headers = Set.new
      end

      # Yields the IO the caller should write to, then emits everything written as one block,
      # preceded by whichever of headers has not been printed yet.
      #
      # @param headers [Array<Array(Object, String)>] [key, line] pairs, each printed at most
      #   once per writer.
      def capture(headers: [])
        unless @buffered
          print_with_headers(headers)
          return yield(@output)
        end

        buffer = StringIO.new

        begin
          yield(buffer)
        ensure
          # In an ensure so an execution killed part way through still gets the lines it
          # managed to produce onto the console.
          flush(headers, buffer.string)
        end
      end

      # Headers and lines in one acquisition of the lock, for a caller whose lines are only
      # attributable underneath its own header. Two calls would let another execution's flush
      # land between the two.
      #
      # @param headers [Array<Array(Object, String)>] [key, line] pairs, each printed at most
      #   once per writer.
      def print_with_headers(headers, *lines)
        @mutex.synchronize do
          write_headers(headers)
          @output.puts(*lines) if lines.any?
        end
      end

    private

      def flush(headers, string)
        @mutex.synchronize do
          write_headers(headers)
          @output.write(string) unless string.empty?
        end
      end

      def write_headers(headers)
        headers.compact.each do |key, line|
          @output.puts(line) if @printed_headers.add?(key)
        end
      end
    end
  end
end
