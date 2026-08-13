# frozen_string_literal: true

# Shared advisory lock serializing every destructive archive operation:
# Raif::ArchiveModelCompletionsJob and Raif::Archive.purge_partition! must
# never interleave, or a concurrent archive run could write fresh objects
# into a partition prefix mid-purge and leave them behind.
module Raif::ArchiveAdvisoryLock
  NAME = "raif_archive_model_completions"

  # Session-level and non-blocking: runs the block with the lock held and
  # returns true, or returns false without running it when another session
  # holds the lock. Callers choose their busy behavior (the job skips the
  # run; purge raises a retryable error). Adapters without advisory lock
  # support (neither PG nor MySQL) run unguarded; hosts control scheduling
  # anyway.
  def self.acquire
    connection = Raif::ModelCompletion.connection
    unless connection.respond_to?(:get_advisory_lock)
      Rails.logger.warn(
        "Raif::ArchiveAdvisoryLock: this database adapter does not support advisory locks; running unguarded " \
          "(concurrent archive runs and partition purges cannot be excluded from each other)"
      )
      yield
      return true
    end

    # Stable across processes (String#hash is per-process salted) and
    # within PG's signed bigint range.
    lock_id = Digest::SHA256.hexdigest(NAME)[0, 15].to_i(16)
    return false unless connection.get_advisory_lock(lock_id)

    begin
      yield
      true
    ensure
      connection.release_advisory_lock(lock_id)
    end
  end
end
