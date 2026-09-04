# frozen_string_literal: true

# Fails fast on invalid numeric options, before credential setup or live API calls.
module Smoke
  def self.validate_options!(options, parser)
    parser.abort("--iterations must be greater than 0") unless options[:iterations].positive?
    parser.abort("--batch-timeout must be greater than 0") unless options[:batch_timeout].positive?
    parser.abort("--stale must be 0 or greater") if options[:stale_days]&.negative?
  end
end
