# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ConsoleWriter do
  # An IO that gives up the GVL between lines, so anything writing to it without holding a lock
  # will interleave with a concurrent writer. A plain StringIO would not: its writes are short
  # enough to usually complete within one thread's turn, which would let an unsynchronized
  # writer pass by luck.
  class SlowIo
    attr_reader :lines

    def initialize
      @lines = []
    end

    def puts(*args)
      write(args.flatten.map { |arg| "#{arg}\n" }.join)
    end

    def write(string)
      string.each_line do |line|
        @lines << line.chomp
        sleep 0.001
      end
    end
  end

  def write_block(writer, name, headers: [])
    writer.capture(headers: headers) do |io|
      io.puts "#{name} first"
      sleep 0.001
      io.puts "#{name} second"
      sleep 0.001
      io.puts "#{name} third"
    end
  end

  def in_threads(names, &block)
    names.map { |name| Thread.new { block.call(name) } }.each(&:join)
  end

  describe "buffered" do
    let(:io) { SlowIo.new }
    let(:writer) { described_class.new(io, buffered: true) }

    it "emits each block's lines contiguously, whatever else is writing" do
      in_threads(["a", "b", "c", "d"]) { |name| write_block(writer, name) }

      expect(io.lines.count).to eq(12)

      io.lines.each_slice(3) do |first, second, third|
        name = first.split.first
        expect([second, third]).to eq(["#{name} second", "#{name} third"])
      end
    end

    it "prints each header once, before the first block that declares it" do
      header = ["the-key", "the header"]

      in_threads(["a", "b", "c"]) { |name| write_block(writer, name, headers: [header]) }

      expect(io.lines.count(&"the header".method(:==))).to eq(1)
      expect(io.lines.first).to eq("the header")
    end

    it "ignores nil headers, which is what an eval with no description line hands it" do
      writer.capture(headers: [nil, ["key", "kept"]]) { |io_| io_.puts "line" }

      expect(io.lines).to eq(["kept", "line"])
    end

    # An execution killed part way through has still produced lines worth seeing.
    it "flushes what a block wrote before it raised" do
      expect do
        writer.capture(headers: [["key", "header"]]) do |io_|
          io_.puts "before the failure"
          raise "boom"
        end
      end.to raise_error(RuntimeError, "boom")

      expect(io.lines).to eq(["header", "before the failure"])
    end

    it "writes nothing for a block that produced no output" do
      writer.capture(headers: []) { |_io| nil }

      expect(io.lines).to be_empty
    end
  end

  describe "unbuffered" do
    let(:io) { SlowIo.new }
    let(:writer) { described_class.new(io, buffered: false) }

    # A serial run has nothing to interleave with, and writing through is what keeps a slow
    # eval's lines appearing as it produces them rather than all at once when it finishes.
    it "writes straight through to the output as the block produces lines" do
      writer.capture(headers: [["key", "header"]]) do |io_|
        io_.puts "first"
        expect(io.lines).to eq(["header", "first"])
        io_.puts "second"
      end

      expect(io.lines).to eq(["header", "first", "second"])
    end

    it "still prints a header only once" do
      2.times { |i| writer.capture(headers: [["key", "header"]]) { |io_| io_.puts "line #{i}" } }

      expect(io.lines).to eq(["header", "line 0", "line 1"])
    end
  end

  describe "#print_with_headers" do
    let(:io) { SlowIo.new }
    let(:writer) { described_class.new(io, buffered: true) }

    it "prints a header that no block has claimed yet, and suppresses it afterwards" do
      writer.print_with_headers([["key", "header"]])
      write_block(writer, "a", headers: [["key", "header"]])

      expect(io.lines).to eq(["header", "a first", "a second", "a third"])
    end

    # The eval set banner and the summary line beneath it are only attributable together, so a
    # concurrently flushing execution must not be able to land between them.
    it "emits its header and lines without another writer interleaving between them" do
      other = Thread.new { write_block(writer, "b") }
      writer.print_with_headers([["key", "header"]], "summary one", "summary two")
      other.join

      expect(io.lines.each_cons(3)).to include(["header", "summary one", "summary two"])
    end
  end
end
