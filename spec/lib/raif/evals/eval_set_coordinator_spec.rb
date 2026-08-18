# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::Evals::EvalSetCoordinator do
  # Instances the eval blocks actually ran on, so a spec can assert the coordinator handed each
  # execution its own rather than reusing one.
  let(:runners) { [] }

  let(:eval_set_class) do
    instances = runners

    Class.new(Raif::Evals::EvalSet) do
      dataset :numbers do
        [{ id: "alpha", input: { "n" => 1 } }, { id: "beta", input: { "n" => 2 } }]
      end

      eval "doubles its input", dataset: :numbers do |eval_case|
        instances << self
        expect("positive") { eval_case["n"].positive? }
      end

      eval "runs without a dataset" do
        instances << self
        expect("always") { true }
      end
    end
  end

  let(:coordinator) { described_class.new(eval_set_class: eval_set_class, output: StringIO.new) }

  it "is not itself an eval set" do
    expect(coordinator).not_to be_a(Raif::Evals::EvalSet)
    expect(coordinator.eval_set_class).to eq(eval_set_class)
  end

  describe "#pending_executions" do
    it "lists one execution per eval, per case, per repeat" do
      executions = coordinator.pending_executions(repeats: 2)

      expect(executions.map { |e| [e.eval_index, e.eval_case&.id, e.run_index] }).to eq([
        [0, "alpha", 1], [0, "alpha", 2], [0, "beta", 1], [0, "beta", 2],
        [1, nil, 1], [1, nil, 2]
      ])
    end

    it "does not run any of them" do
      coordinator.pending_executions(repeats: 2)

      expect(runners).to be_empty
    end

    it "applies the case selection the coordinator was built with" do
      selective = described_class.new(eval_set_class: eval_set_class, output: StringIO.new, cases: ["beta"])

      expect(selective.pending_executions.map { |e| e.eval_case&.id }).to eq(["beta", nil])
      expect(selective.result_order).to eq({ [0, "beta"] => 0, [1, nil] => 0 })
    end

    # Resolving a dataset runs a user block, reads fixture files, and draws the sample. Every
    # method reads one resolution, so a second call cannot pick different cases.
    it "resolves its datasets once, however many times it is asked what to run" do
      resolutions = 0
      allow(eval_set_class).to receive(:new).and_wrap_original do |original, **kwargs|
        resolutions += 1
        original.call(**kwargs)
      end

      coordinator.pending_executions(repeats: 1)
      coordinator.result_order
      coordinator.pending_executions(repeats: 2)

      # One eval set instance for the dataset resolution, and none since - the instances that
      # run executions are built in #run_and_record, which nothing here reached.
      expect(resolutions).to eq(1)
    end
  end

  describe "#result_order" do
    it "maps each [eval_index, case_id] to its position in definition order" do
      expect(coordinator.result_order).to eq({
        [0, "alpha"] => 0,
        [0, "beta"] => 1,
        [1, nil] => 0
      })
    end
  end

  describe "#run" do
    it "returns one result per execution" do
      results = coordinator.run

      expect(results).to all(be_a(Raif::Evals::EvalResult))
      expect(results.map { |result| [result.eval_index, result.case_id] })
        .to eq([[0, "alpha"], [0, "beta"], [1, nil]])
      expect(results).to all(be_passed)
    end

    # The reason the coordinator is not an EvalSet: run_eval writes the current case and result
    # onto the instance it runs on, so sharing one would cap the run at a single execution in
    # flight and leak whatever setup left behind into the next eval.
    it "runs each execution on its own eval set instance" do
      coordinator.run

      expect(runners.length).to eq(3)
      expect(runners.map(&:object_id).uniq.length).to eq(3)
      expect(runners).to all(be_a(eval_set_class))
      expect(runners).not_to include(coordinator)
    end
  end

  describe "#run_and_record" do
    it "records each result to the run log as it completes" do
      log = instance_spy(Raif::Evals::RunLog, recorded?: false)
      coordinator = described_class.new(eval_set_class: eval_set_class, output: StringIO.new, run_log: log)

      coordinator.run

      expect(log).to have_received(:record).exactly(3).times
    end

    it "skips executions the run log already holds" do
      log = instance_spy(Raif::Evals::RunLog)
      allow(log).to receive(:recorded?).and_return(false)
      allow(log).to receive(:recorded?).with(hash_including(case_id: "alpha")).and_return(true)

      coordinator = described_class.new(eval_set_class: eval_set_class, output: StringIO.new, run_log: log)

      expect(coordinator.run.map(&:case_id)).to eq(["beta", nil])
    end
  end
end
