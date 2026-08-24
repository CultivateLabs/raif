# frozen_string_literal: true

require "set"

module Raif
  module Evals
    # The executions a run set out to perform, fixed once its datasets are resolved and before its
    # first eval runs.
    #
    # A run log records what a run has already done. On its own that says nothing about what the
    # run still owes, so anything narrower than the original invocation - `--resume` given one eval
    # set file - would drain its own shorter work list, write the results file and delete the log
    # while the rest of the run was still outstanding. The plan is what lets the log answer whether
    # the run is finished, rather than the invocation answering it for itself.
    #
    # A key is Raif::Evals::RunLog.key: which eval block, against which case, on which repeat.
    class RunPlan
      # The shape of a persisted plan. A log written under a version this code cannot read is not
      # resumable, since these keys are how a resume tells what is done from what is outstanding.
      VERSION = 1

      attr_reader :keys

      def initialize(keys:)
        @keys = keys.map { |key| self.class.normalize(key) }.uniq
      end

      # nil for anything this version cannot read, including a log written before plans existed.
      # Raif::Evals::RunLog is what reports on that, so that every reason a resume is refused is
      # phrased in one place.
      def self.from_h(data)
        return unless data.is_a?(Hash)
        return unless data[:version].to_i == VERSION

        new(keys: Array(data[:keys]))
      end

      # JSON has no symbols and no tuples, so a key read back out of a log is an array of strings,
      # integers and nulls. Coerced on the way in rather than compared loosely at every use.
      def self.normalize(key)
        eval_id, case_id, run_index = key

        [eval_id.to_s, case_id&.to_s, run_index&.to_i]
      end

      def to_h
        { version: VERSION, keys: keys }
      end

      def size
        keys.length
      end

      def include?(key)
        key_set.include?(self.class.normalize(key))
      end

      # The planned keys no result has been recorded for, in plan order.
      def outstanding(recorded_keys)
        recorded = recorded_keys.map { |key| self.class.normalize(key) }.to_set

        keys.reject { |key| recorded.include?(key) }
      end

      # The keys of another plan this one does not already hold, in that plan's order. A resumed
      # invocation can turn up executions the original run never planned - an eval block added to a
      # file while the run was interrupted - and those are work the run now owes too.
      def additions(other)
        other.keys.reject { |key| include?(key) }
      end

      def plus(additional_keys)
        self.class.new(keys: keys + additional_keys)
      end

    private

      def key_set
        @key_set ||= keys.to_set
      end
    end
  end
end
