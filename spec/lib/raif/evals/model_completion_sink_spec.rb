# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::ModelCompletionSink do
  # Plain objects: the sink does not care what it collects, and the thread examples below must
  # not touch the DB.
  let(:completion) { Object.new }

  after { described_class.close }

  it "collects into the array #open returned" do
    collected = described_class.open
    described_class.record(completion)

    expect(collected).to eq([completion])
  end

  it "collects in the order the completions were created" do
    first = Object.new
    second = Object.new
    collected = described_class.open

    described_class.record(first)
    described_class.record(second)

    expect(collected).to eq([first, second])
  end

  # Reached for every Raif::ModelCompletion insert in a process that has loaded the evals, this
  # suite included, so the closed case is the common one.
  it "is a no-op when nothing is collecting" do
    expect { described_class.record(completion) }.not_to raise_error
  end

  it "stops collecting after #close" do
    collected = described_class.open
    described_class.close
    described_class.record(completion)

    expect(collected).to be_empty
  end

  it "starts each #open with an empty sink rather than extending the last one" do
    described_class.open
    described_class.record(completion)

    expect(described_class.open).to be_empty
  end

  # What keeps capture correct once evals run concurrently: an eval sees only the calls made on
  # its own thread, never a sibling eval's.
  it "does not collect completions recorded on another thread" do
    collected = described_class.open

    Thread.new { described_class.record(completion) }.join

    expect(collected).to be_empty
  end

  # app/models/raif/evals makes Raif::Evals a Zeitwerk-managed namespace, so a reload drops the
  # constants raif/evals.rb required into it. A subscriber that resolved the constant per event
  # would start raising on a host app's own LLM calls.
  it "keeps recording when Raif::Evals no longer holds the constant, as a reload leaves it" do
    sink = described_class
    collected = sink.open
    Raif::Evals.send(:remove_const, :ModelCompletionSink)

    begin
      expect { ActiveSupport::Notifications.instrument("create.raif_model_completion", model_completion: :a_completion) }
        .not_to raise_error
      expect(collected).to eq([:a_completion])
    ensure
      Raif::Evals.const_set(:ModelCompletionSink, sink)
    end
  end

  it "leaves an enclosing thread's sink alone when another thread opens its own" do
    outer = described_class.open

    Thread.new do
      described_class.open
      described_class.record(completion)
    end.join

    described_class.record(:from_the_original_thread)
    expect(outer).to eq([:from_the_original_thread])
  end
end
