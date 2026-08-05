# frozen_string_literal: true

module Raif
  module Evals
    # Compact output and the text comparison report both put an expectation description on
    # a single line. An LLM judge expectation's description is its entire criteria - several
    # hundred characters of prompt - and the same one repeats under every case that failed
    # it, so untruncated it buries the case ids and pass counts the line exists to show.
    # The full text is still in the results JSON, the HTML report, and --verbose output.
    module ConsoleLine
      MAX_DESCRIPTION_LENGTH = 100

      def self.truncate_description(description, limit: MAX_DESCRIPTION_LENGTH)
        text = description.to_s
        return text if text.length <= limit

        "#{text[0, limit].rstrip}..."
      end
    end
  end
end
