# frozen_string_literal: true

require "digest"
require "json"

module Raif
  module Evals
    # An ordered, named collection of EvalCases, built from whatever the eval set's
    # `dataset` block returned.
    #
    # Validation raises rather than warns, and runs before any eval executes: a dataset whose
    # cases cannot be told apart produces results that cannot be joined against a previous
    # run, and finding that out after paying for the inference is too late.
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

      # A fingerprint of what this dataset holds, recorded in the run's configuration so two runs
      # can tell whether they measured the same inputs. Without it an edited case reads as a model
      # regression: evals:compare joins on case id, so the same id carrying a different input is
      # reported as the model behaving differently on the same one.
      #
      # Over the whole dataset rather than the selected cases, since --cases, --sample and --seed
      # are recorded beside it and already say which of these ran.
      def digest
        @digest ||= "sha256:#{Digest::SHA256.hexdigest(canonical_cases)}"
      end

      # ids and sample are run-wide (--cases / --sample), so an id belonging to another eval
      # set's dataset filters this one to nothing rather than raising. Run#execute errors
      # when a selection matched no case anywhere.
      def select_cases(ids: nil, sample: nil, seed: nil)
        selected = cases

        if ids
          wanted = Array(ids).map(&:to_s).to_set
          selected = selected.select { |eval_case| wanted.include?(eval_case.id) }
        end

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

      # Sorted by id and with every hash key sorted, so a fingerprint tracks what the cases are
      # rather than how the file is arranged: reordering rows or reformatting them leaves it alone,
      # editing an input changes it.
      def canonical_cases
        cases.sort_by(&:id).map { |eval_case| JSON.generate(canonicalize(eval_case.to_h)) }.join("\n")
      end

      # Keys stringified as well as sorted, so a case written with symbol keys in a Ruby dataset
      # block fingerprints the same as the same case read out of a JSONL file. Anything that is not
      # JSON-native goes through to_s rather than to JSON's rendering of an arbitrary object, which
      # can carry a memory address and so differ between two runs of identical cases.
      def canonicalize(value)
        case value
        when Hash then value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(value[key])] }
        when Array then value.map { |element| canonicalize(element) }
        when String, Numeric, true, false, nil then value
        else value.to_s
        end
      end

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
          # Key presence, not `||`: a binary-classification case can legitimately expect
          # `false`, which a fallback would silently turn into `nil`.
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
