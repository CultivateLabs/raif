# frozen_string_literal: true

module Raif::Concerns::HasRuntimeDuration
  extend ActiveSupport::Concern

  def runtime_ended_at
    completed_at || failed_at
  end

  def runtime_duration_seconds
    return nil if started_at.blank? || runtime_ended_at.blank?

    duration_in_seconds = runtime_ended_at - started_at
    return nil if duration_in_seconds.negative?

    duration_in_seconds
  end

  def runtime_duration
    duration_in_seconds = runtime_duration_seconds
    return "-" if duration_in_seconds.nil?

    if duration_in_seconds < 1
      "#{(duration_in_seconds * 1000).round}ms"
    elsif duration_in_seconds < 60
      seconds = (duration_in_seconds * 100).round / 100.0
      "#{seconds.to_s.sub(/\.0+\z/, "").sub(/(\.\d*[1-9])0+\z/, "\\1")}s"
    else
      total_seconds = duration_in_seconds.round
      hours = total_seconds / 3600
      minutes = (total_seconds % 3600) / 60
      seconds = total_seconds % 60

      parts = []
      parts << "#{hours}h" if hours.positive?
      parts << "#{minutes}m" if minutes.positive? || hours.positive?
      parts << "#{seconds}s"
      parts.join(" ")
    end
  end
end
