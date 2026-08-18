# frozen_string_literal: true

module Raif
  module Evals
    module EvalSets
      # Matchers for evals with a known-correct answer, typically an EvalCase's `expected`.
      #
      # Each one wraps #expect. What they add over a hand-written block is normalization applied
      # the same way in every eval set, and metadata: a hand-written `include?` records only that
      # it failed, where these record what was produced and what was wanted.
      module Matchers
        # Both sides of a comparison land in the results JSON for every case of every repeat, and
        # an untruncated response is most of the file.
        MAX_METADATA_LENGTH = 500

        # Descriptions omit the expected value: evals:compare tallies an expectation across the
        # cases of an eval by its description (Comparison#worst_expectation_drop), so case data in
        # one splits it into a tally per case and the gate reads a rate measured on a single case.
        # A tolerance is written in the eval block rather than the dataset, so it is stable.

        # Compares a value against ground truth, ignoring the differences a case or whitespace
        # change makes. Strings are normalized and compared; anything else is compared with ==,
        # so a boolean or numeric answer is not coerced through to_s first.
        #
        # @param actual [Object] the value produced by whatever is under test
        # @param expected [Object] the ground-truth value
        # @param ignore_case [Boolean] downcase both sides before comparing (strings only)
        # @param strip [Boolean] strip surrounding whitespace from both sides (strings only)
        # @param label [String, nil] replaces the expectation's description
        # @param result_metadata [Hash] merged into the recorded metadata
        #
        # @return [ExpectationResult]
        #
        # @example
        #   expect_exact_match(task.parsed_response, eval_case.expected["answer"])
        def expect_exact_match(actual, expected, ignore_case: true, strip: true, label: nil, result_metadata: {})
          normalized_actual = normalize_matcher_string(actual, ignore_case: ignore_case, strip: strip)
          normalized_expected = normalize_matcher_string(expected, ignore_case: ignore_case, strip: strip)

          metadata = result_metadata.merge(matcher_metadata(actual, expected))

          expect label || "exact match", result_metadata: metadata do
            normalized_actual == normalized_expected
          end
        end

        # Asserts that text appears in a value. An Array of expected texts requires all of them,
        # which is the common shape of "the summary has to mention each of these".
        #
        # @param actual [Object] the value produced by whatever is under test, read as text
        # @param expected [String, Array<String>] the text, or every text, that must appear
        # @param ignore_case [Boolean] compare with both sides downcased
        # @param label [String, nil] replaces the expectation's description
        # @param result_metadata [Hash] merged into the recorded metadata
        #
        # @return [ExpectationResult]
        #
        # @example
        #   expect_includes(task.parsed_response, eval_case.expected["keywords"])
        def expect_includes(actual, expected, ignore_case: true, label: nil, result_metadata: {})
          haystack = actual.to_s
          haystack = haystack.downcase if ignore_case
          needles = Array(expected).map(&:to_s)

          # Recorded rather than merely counted: which of five keywords went missing is what
          # makes the failure debuggable.
          missing = needles.reject do |needle|
            haystack.include?(ignore_case ? needle.downcase : needle)
          end

          metadata = result_metadata.merge(matcher_metadata(actual, expected)).merge(missing: missing)

          expect label || "includes expected text", result_metadata: metadata do
            needles.any? && missing.empty?
          end
        end

        # Asserts that a value matches a pattern. A String pattern is compiled, so a dataset row
        # can carry one.
        #
        # @param actual [Object] the value produced by whatever is under test, read as text
        # @param pattern [Regexp, String] the pattern to match
        # @param label [String, nil] replaces the expectation's description
        # @param result_metadata [Hash] merged into the recorded metadata
        #
        # @return [ExpectationResult]
        #
        # @example
        #   expect_matches(task.parsed_response, /\A[A-Z]{2}-\d{4}\z/)
        def expect_matches(actual, pattern, label: nil, result_metadata: {})
          regexp = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s)
          metadata = result_metadata.merge(matcher_metadata(actual, regexp.source)).merge(pattern: regexp.inspect)

          expect label || "matches expected pattern", result_metadata: metadata do
            regexp.match?(actual.to_s)
          end
        end

        # Asserts that a number is close enough to ground truth. Mirrors RSpec's
        # `be_within(delta).of(expected)`, with percent: as the relative alternative.
        #
        # A non-numeric actual fails rather than raises: a model that answered "about forty" when
        # the eval asked for a number produced a wrong answer, not a broken eval. A non-numeric
        # expected raises, because only the eval's author can have put it there.
        #
        # @param actual [Object] the value produced by whatever is under test
        # @param expected [Numeric] the ground-truth value
        # @param delta [Numeric, nil] the absolute tolerance; give this or percent:, not both
        # @param percent [Numeric, nil] the tolerance as a percentage of expected
        # @param label [String, nil] replaces the expectation's description
        # @param result_metadata [Hash] merged into the recorded metadata
        #
        # @raise [ArgumentError] when expected is not numeric, or the tolerance is not exactly one
        #   of delta: and percent:
        #
        # @return [ExpectationResult]
        #
        # @example
        #   expect_within(task.parsed_response["total"], eval_case.expected["total"], percent: 1)
        def expect_within(actual, expected, delta: nil, percent: nil, label: nil, result_metadata: {})
          if delta.nil? == percent.nil?
            raise ArgumentError, "expect_within needs exactly one of delta: and percent:, and was given " \
              "#{delta.nil? ? "neither" : "both"}."
          end

          unless expected.is_a?(Numeric)
            raise ArgumentError, "expect_within was given #{expected.inspect} as the expected value; it must be numeric."
          end

          # A percentage of zero is zero, so a zero expected admits only an exact zero.
          tolerance = delta || (expected.abs * percent.to_f / 100.0)
          difference = (actual - expected).abs if actual.is_a?(Numeric)

          metadata = result_metadata
            .merge(matcher_metadata(actual, expected))
            .merge({ tolerance: tolerance.to_f, difference: difference&.to_f }.compact)

          description = delta ? "within #{delta} of expected" : "within #{percent}% of expected"

          expect label || description, result_metadata: metadata do
            !difference.nil? && difference <= tolerance
          end
        end

      private

        def normalize_matcher_string(value, ignore_case:, strip:)
          return value unless value.is_a?(String)

          value = value.strip if strip
          value = value.downcase if ignore_case
          value
        end

        def matcher_metadata(actual, expected)
          { actual: truncate_matcher_value(actual), expected: truncate_matcher_value(expected) }
        end

        # Non-strings are inspected first, so an Array of expected keywords reaches the JSON as
        # something a reader can act on.
        def truncate_matcher_value(value)
          text = value.is_a?(String) ? value : value.inspect
          return text if text.length <= MAX_METADATA_LENGTH

          "#{text[0, MAX_METADATA_LENGTH]}..."
        end
      end
    end
  end
end
