# frozen_string_literal: true

module Raif
  module Evals
    # A number recorded by an eval, as opposed to the yes/no an ExpectationResult carries.
    #
    # scale and higher_is_better travel with the value because evals:compare cannot otherwise
    # tell an improvement from a regression - a latency that halved and a score that halved
    # are the same arithmetic and opposite news.
    class ScoreResult
      attr_reader :name, :value, :scale, :min, :max

      def initialize(name:, value:, scale: nil, higher_is_better: true, min: nil, max: nil)
        # Checked rather than left to to_f, which turns nil and any non-numeric into a silent
        # 0.0 - dragging the mean toward zero and, against a max: ceiling, reporting a missing
        # measurement as the best possible result and passing the gate on it.
        unless value.is_a?(Numeric)
          raise ArgumentError, "score #{name.to_s.inspect} was given #{value.inspect}; a score value must be numeric"
        end

        @name = name.to_s
        @value = value.to_f
        @scale = scale
        @higher_is_better = higher_is_better
        @min = min
        @max = max
      end

      def higher_is_better?
        @higher_is_better
      end

      def gated?
        !min.nil? || !max.nil?
      end

      def passed?
        (min.nil? || value >= min) && (max.nil? || value <= max)
      end

      # Becomes the gating expectation's description, which evals:compare matches results on
      # across runs.
      def gate_description
        bounds = []
        bounds << ">= #{min}" unless min.nil?
        bounds << "<= #{max}" unless max.nil?

        "#{name} score #{bounds.join(" and ")}"
      end

      # Integral values print without a trailing zero, so a 1-5 rubric score reads as "4" in
      # a console line that already has several numbers in it.
      def formatted_value
        (value % 1).zero? ? value.to_i.to_s : value.round(4).to_s
      end

      def to_h
        {
          name: name,
          value: value,
          scale: scale&.to_s,
          higher_is_better: higher_is_better?,
          min: min,
          max: max,
          passed: (passed? if gated?)
        }.compact
      end
    end
  end
end
