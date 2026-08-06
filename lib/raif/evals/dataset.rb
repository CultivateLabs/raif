# frozen_string_literal: true

module Raif
  module Evals
    # An ordered, named collection of EvalCases, built from whatever the eval set's
    # `dataset` block returned.
    #
    # Every validation here raises rather than warning, and is performed before the run
    # executes any eval: a dataset whose cases cannot be told apart produces results that
    # cannot be joined against a previous run, and discovering that after paying for the
    # inference is too late to be useful.
    class Dataset
      attr_reader :name, :cases

      def initialize(name:, cases:)
        @name = name
        @cases = build_cases(cases)
        validate_unique_ids!
      end

      def size
        cases.length
      end

      # ids and sample are run-wide selections (--cases / --sample), so an id that belongs
      # to a different eval set's dataset filters this one down to nothing rather than
      # raising. The run as a whole errors when a selection matched no case anywhere.
      def select_cases(ids: nil, sample: nil, seed: nil)
        selected = cases
        selected = selected.select { |eval_case| Array(ids).map(&:to_s).include?(eval_case.id) } if ids
        selected = sample_cases(selected, sample.to_i, seed) if sample && sample.to_i < selected.length

        selected
      end

      def only(ids)
        select_cases(ids: ids)
      end

      def sample(count, seed: nil)
        select_cases(sample: count, seed: seed)
      end

    private

      # Sampled cases keep their dataset order so the console and the results read the same
      # way whether or not a sample was taken.
      def sample_cases(candidates, count, seed)
        random = seed ? Random.new(seed.to_i) : Random.new
        drawn = candidates.shuffle(random: random).take(count)

        candidates.select { |eval_case| drawn.include?(eval_case) }
      end

      def build_cases(rows)
        unless rows.is_a?(Array)
          raise ArgumentError, "dataset #{name.inspect} returned #{rows.class}; a dataset block must return an array of case hashes"
        end

        rows.each_with_index.map do |row, index|
          next row if row.is_a?(EvalCase)

          unless row.is_a?(Hash)
            raise ArgumentError, "dataset #{name.inspect} case at index #{index} is #{row.class}; each case must be a Hash with :id and :input"
          end

          id = row[:id] || row["id"]
          input = row.key?(:input) ? row[:input] : row["input"]
          # Read expected by key presence, not `||`: a binary-classification case can legitimately
          # expect `false`, which a fallback would silently turn into `nil`.
          expected = row.key?(:expected) ? row[:expected] : row["expected"]

          raise ArgumentError, "dataset #{name.inspect} case at index #{index} is missing an :id" if id.nil? || id.to_s.strip.empty?
          raise ArgumentError, "dataset #{name.inspect} case #{id.to_s.inspect} is missing an :input" if input.nil?

          EvalCase.new(id: id, input: input, expected: expected)
        end
      end

      def validate_unique_ids!
        duplicates = cases.map(&:id).tally.select { |_id, count| count > 1 }.keys
        return if duplicates.empty?

        raise ArgumentError, "dataset #{name.inspect} has duplicate case ids: #{duplicates.map(&:inspect).join(", ")}"
      end
    end
  end
end
