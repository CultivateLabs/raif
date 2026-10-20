# frozen_string_literal: true

module Raif
  # Line-level diff of two prompts, with word-level highlighting inside changed line pairs.
  # Returns plain data so views can render (and escape) the text themselves.
  class PromptDiff
    # Lines with more tokens than this skip the word diff and are highlighted as a whole.
    WORD_DIFF_TOKEN_LIMIT = 2_000

    Line = Struct.new(:action, :segments) # action: :unchanged, :deleted, :added
    Segment = Struct.new(:text, :changed)

    def self.build(original, current)
      new(original, current).lines
    end

    def initialize(original, current)
      @original_lines = original.to_s.strip.lines(chomp: true)
      @current_lines = current.to_s.strip.lines(chomp: true)
    end

    def lines
      result = []
      deleted = []
      added = []

      Diff::LCS.sdiff(@original_lines, @current_lines).each do |change|
        case change.action
        when "="
          result.concat(deleted).concat(added)
          deleted = []
          added = []
          result << Line.new(:unchanged, [Segment.new(change.old_element, false)])
        when "-"
          deleted << Line.new(:deleted, [Segment.new(change.old_element, true)])
        when "+"
          added << Line.new(:added, [Segment.new(change.new_element, true)])
        when "!"
          old_segments, new_segments = word_diff(change.old_element, change.new_element)
          deleted << Line.new(:deleted, old_segments)
          added << Line.new(:added, new_segments)
        end
      end

      result.concat(deleted).concat(added)
    end

  private

    def word_diff(old_line, new_line)
      old_tokens = tokenize(old_line)
      new_tokens = tokenize(new_line)

      if old_tokens.size > WORD_DIFF_TOKEN_LIMIT || new_tokens.size > WORD_DIFF_TOKEN_LIMIT
        return [[Segment.new(old_line, true)], [Segment.new(new_line, true)]]
      end

      old_segments = []
      new_segments = []

      Diff::LCS.sdiff(old_tokens, new_tokens).each do |change|
        unchanged = change.action == "="
        append_segment(old_segments, change.old_element, !unchanged) if change.old_element && change.action != "+"
        append_segment(new_segments, change.new_element, !unchanged) if change.new_element && change.action != "-"
      end

      [old_segments, new_segments]
    end

    def tokenize(line)
      line.scan(/\w+|\s+|[^\w\s]/)
    end

    # Merges consecutive tokens with the same changed flag into one segment.
    def append_segment(segments, text, changed)
      if segments.last&.changed == changed
        segments.last.text += text
      else
        segments << Segment.new(+text, changed)
      end
    end
  end
end
