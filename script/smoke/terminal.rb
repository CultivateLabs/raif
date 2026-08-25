# frozen_string_literal: true

# Raw-ANSI terminal formatting for bin/smoke: colored output plus a dependency-free [y/N]
# confirmation prompt. No gem dependency (e.g. no `colorize`/`tty-prompt`) -- bin/smoke is a
# maintenance script, not the gem's runtime, but it still shouldn't grow a new dependency for
# cosmetics.
#
# Every color-producing method accepts the stream it will be written to (colors_enabled? checks
# that stream's own tty-ness, since stdout and stderr can be redirected independently -- piping
# stdout to `head` while stderr still reaches a real terminal, or vice versa) and an `enabled:`
# override that bypasses the tty/env detection entirely. Specs use `enabled:` directly rather than
# faking a tty, since there's no real terminal available in a test run.
module Smoke
  module Terminal
    CODES = {
      green: 32,
      red: 31,
      yellow: 33,
      cyan: 36,
      bold: 1,
      dim: 2
    }.freeze

    RESET = "\e[0m"

    STATUS_COLORS = {
      pass: :green,
      fail: :red,
      timeout: :red,
      skip: :yellow,
      note: :cyan,
      # A claimed-false capability the provider rejected as declared: agreement with the
      # manifest, not something to celebrate (pass/green) or worry about (fail/red) -- dim
      # de-emphasizes it the way a benign, expected result should read.
      consistent: :dim
    }.freeze

    # Set by --no-color. Sticky for the rest of the process -- there is no re-enable, since a
    # single bin/smoke invocation never needs one.
    def self.disable_colors!
      @no_color_flag = true
    end

    def self.colors_enabled?(stream)
      stream.tty? && ENV["NO_COLOR"].nil? && !@no_color_flag
    end

    # Returns text unchanged when colors are disabled for stream, so piped/non-tty output is
    # byte-identical to a build with no color support at all.
    def self.paint(text, color, stream: $stdout, enabled: colors_enabled?(stream))
      return text.to_s unless enabled

      "\e[#{CODES.fetch(color)}m#{text}#{RESET}"
    end

    def self.status_paint(label, status, stream: $stdout, enabled: colors_enabled?(stream))
      color = STATUS_COLORS[status]
      return label.to_s unless color

      paint(label, color, stream: stream, enabled: enabled)
    end

    # Prompts on stderr, since progress lines already go there. Only an explicit y/yes
    # (case-insensitive) counts as confirmation.
    def self.confirm?(question)
      $stderr.print("#{question} [y/N] ")
      $stderr.flush
      answer = $stdin.gets
      !!(answer && answer.strip.match?(/\A(y|yes)\z/i))
    end

    # "MM:SS", or "H:MM:SS" once the duration reaches an hour.
    def self.format_duration(seconds)
      total_seconds = seconds.round
      hours, remainder = total_seconds.divmod(3600)
      minutes, secs = remainder.divmod(60)

      return format("%d:%02d:%02d", hours, minutes, secs) if hours.positive?

      format("%02d:%02d", minutes, secs)
    end
  end
end
