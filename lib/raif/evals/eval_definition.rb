# frozen_string_literal: true

require "digest"

module Raif
  module Evals
    # One `eval "..." do ... end` declaration: the block, what it is called, and the dataset it
    # runs over. The definition, not the outcome - running one of these once against one case
    # produces an EvalResult.
    #
    # index is the definition's position in its eval set, assigned when it registers. Results are
    # grouped by it when repeats are collapsed into a pass rate, and sorted by it back into
    # definition order. It is deliberately not the identity: see #id.
    class EvalDefinition
      # Caps the readable half so a sentence-long description does not produce an id that wraps a
      # terminal. Truncating it is safe: the digest, not the slug, is what makes an id unique.
      DESCRIPTION_SLUG_LIMIT = 60

      # 48 bits. A collision only matters within one eval set, and the duplicate-description check
      # already refuses the realistic way that happens.
      DIGEST_LENGTH = 12

      attr_reader :description, :block, :dataset, :index, :file, :line_number, :eval_set_class, :declared_id

      def initialize(description:, block:, index:, eval_set_class:, declared_id: nil, dataset: nil, file: nil, line_number: nil)
        @description = description
        @block = block
        @dataset = dataset
        @index = index
        @eval_set_class = eval_set_class
        @declared_id = declared_id
        @file = file
        @line_number = line_number
      end

      # What identifies this eval across runs: the key evals:compare joins on and --resume skips
      # already-recorded work by. Position cannot do that job, since inserting an eval block shifts
      # every index below it and a comparison would then join one eval's baseline to another eval's
      # candidate with nothing looking wrong.
      #
      # Derived rather than declared so nothing has to be hand-written: class name, a slug of the
      # description, and a digest over both. The digest is the identifying half and is taken over
      # the description verbatim, so "handles > 100 items" and "handles < 100 items" stay distinct
      # despite slugging identically; the slug is there to make the id readable. Rewording a
      # description therefore produces a new id, which a comparison reports as one eval leaving and
      # another arriving - `id:` is the escape hatch when the wording changed but the eval did not.
      #
      # Computed on first use rather than at registration, because a class assigned to a constant
      # after its body runs - `Foo = Class.new(Raif::Evals::EvalSet) { eval "..." }`, or
      # stub_const - has no name while its evals are registering.
      def id
        @id ||= "#{eval_set_name}##{declared_id || derived_suffix}"
      end

      def dataset?
        !dataset.nil?
      end

    private

      def eval_set_name
        name = eval_set_class.name

        # Nothing stable to derive from: #<Class:0x...> changes every process, so ids would be
        # unique per run and every comparison would come back NOT COMPARABLE with no visible cause.
        if name.nil?
          raise ArgumentError, "the eval set declaring #{description.inspect} is an anonymous class, so its evals have no " \
            "identity that survives the process. Assign the eval set to a constant before running it."
        end

        name
      end

      def derived_suffix
        slug = description_slug
        slug.empty? ? digest : "#{slug}-#{digest}"
      end

      def digest
        Digest::SHA256.hexdigest("#{eval_set_name}\n#{description}")[0, DIGEST_LENGTH]
      end

      # Cut at a separator so the slug ends on a whole word. A description with no separator inside
      # the limit is left as-is rather than emptied.
      def description_slug
        slug = description.to_s.parameterize
        return slug if slug.length <= DESCRIPTION_SLUG_LIMIT

        slug[0, DESCRIPTION_SLUG_LIMIT].sub(/-[^-]*\z/, "").delete_suffix("-")
      end
    end
  end
end
