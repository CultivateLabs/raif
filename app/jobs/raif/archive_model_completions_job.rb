# frozen_string_literal: true

module Raif
  # Archives Raif::ModelCompletion rows older than
  # Raif.config.model_completion_retention_period to
  # Raif.config.archive_storage as gzip JSONL (see Raif::ArchiveSerializer),
  # then deletes them, one Raif::Archive batch at a time.
  #
  # The guarantees are at-least-once archiving + never-delete-unarchived: a
  # batch is deleted only after this run successfully uploaded it, and a
  # re-run after any crash writes a new object under a new key (a harmless
  # duplicate in storage) rather than resuming or overwriting. There is no
  # persisted in-flight state to repair, ever. The flip side is that a crash
  # between upload and the Raif::Archive insert leaves an object in storage
  # with no audit row - the same accepted duplicate class (the rows were not
  # deleted and re-archive next run). Storage-level policy (private bucket,
  # encryption, lifecycle rules) must therefore apply to the whole
  # bucket/prefix, not be derived from raif_archives rows.
  #
  # Inert unless the host explicitly opts in: archive_enabled must be true
  # AND an archive_storage adapter must be configured AND a retention period
  # must be set, otherwise perform returns without touching anything.
  #
  # Hosts own scheduling (raif's usual convention, like
  # Raif::ExpireStuckModelCompletionBatchesJob): run it e.g. nightly.
  # max_batches bounds the work per run; the same code drains a multi-year
  # backlog gradually and handles steady state. Concurrent runs are excluded
  # via an advisory lock. Before enabling, operators can preview with
  # Raif::ArchiveModelCompletionsJob.dry_run.
  #
  # Deliberately NOT handled: raif_model_completion_batches rows remain; they
  # carry their own aggregated cost columns and nothing recomputes them from
  # children after finalization.
  class ArchiveModelCompletionsJob < ApplicationJob
    # Caps are constants, not config: public config is API; add a knob only
    # when a host demonstrably needs it. A batch closes when EITHER cap is
    # hit; the byte cap keeps wildly varying completion payloads (agent
    # message arrays can be enormous) from building a multi-GB tempfile.
    BATCH_RECORD_LIMIT = 25_000
    BATCH_UNCOMPRESSED_BYTE_LIMIT = 512.megabytes
    # Rows updated more recently than this are ineligible for archiving,
    # regardless of age (legitimately active months-old completions can't
    # exist since batch lifetime is capped, but the guard is cheap insurance).
    QUIESCENCE_PERIOD = 24.hours

    KEY_PREFIX = "raif-archives/model-completions"
    ADVISORY_LOCK_NAME = "raif_archive_model_completions"

    class << self
      # A completion is safe to archive and delete only when ALL hold:
      #
      # - created_at is before the (job-frozen) retention cutoff
      # - it has been quiescent: not updated within QUIESCENCE_PERIOD
      # - it is not a member of a model completion batch that is still
      #   non-terminal (belt-and-suspenders alongside quiescence)
      # - durability guard, TERMINAL rows only: its Raif::InferenceCostEvent
      #   exists, so no spend record is ever lost (self-healing after partial
      #   backfills or repair-job lag; an un-evented terminal completion just
      #   waits). Nonterminal rows are eligible without it: they never
      #   reached a terminal state, so no cost event was ever created and
      #   there is no spend to protect. These are orphaned pending rows from
      #   killed processes and crashed jobs (a third of one host's table in
      #   practice) that would otherwise be immortal. They are archived
      #   through the same path as everything else - NOT deleted outright,
      #   despite the temptation (no response, near-zero historical value):
      #   "every deleted completion exists in an archive" must hold without
      #   exception. A delete-without-archive shortcut would be a second
      #   deletion semantics that weakens the invariant this job's safety
      #   rests on, to save pennies of mostly-redundant prompt storage.
      # - durable-citations guard: its citations, if any, have been copied to
      #   its Raif::ConversationEntry source (protects hosts that haven't run
      #   the conversation entry backfill)
      def eligible_scope(cutoff)
        base_scope(cutoff)
          .where(completions_table[:updated_at].lt(QUIESCENCE_PERIOD.ago))
          .where.not(id: active_batch_members)
          .where.not(id: terminal_without_cost_event(cutoff))
          .where.not(id: completions_with_uncopied_citations)
      end

      # Counts what a run under the given cutoff would archive (split by
      # terminal state), plus the per-guard exclusions among cutoff-aged
      # completions. Writes nothing; re-runnable anytime. Operators run this
      # before enabling archiving (defaults to the configured retention
      # period so it can be previewed while archive_enabled is still false).
      def dry_run(cutoff: Raif.config.model_completion_retention_period&.ago)
        raise ArgumentError, "Provide a cutoff: or set Raif.config.model_completion_retention_period" if cutoff.nil?

        eligible = eligible_scope(cutoff)

        {
          cutoff: cutoff,
          eligible: eligible.count,
          eligible_terminal: eligible.where("completed_at IS NOT NULL OR failed_at IS NOT NULL").count,
          eligible_nonterminal: eligible.where(completed_at: nil, failed_at: nil).count,
          excluded_by_quiescence: base_scope(cutoff).where(completions_table[:updated_at].gteq(QUIESCENCE_PERIOD.ago)).count,
          excluded_by_active_batch: base_scope(cutoff).where(id: active_batch_members).count,
          excluded_missing_cost_event: base_scope(cutoff).where(id: terminal_without_cost_event(cutoff)).count,
          excluded_uncopied_citations: base_scope(cutoff).where(id: completions_with_uncopied_citations).count
        }
      end

    private

      def base_scope(cutoff)
        Raif::ModelCompletion.where(completions_table[:created_at].lt(cutoff))
      end

      def terminal_scope(cutoff)
        base_scope(cutoff).where("completed_at IS NOT NULL OR failed_at IS NOT NULL")
      end

      def completions_table
        Raif::ModelCompletion.arel_table
      end

      # Subquery, not a where.not(raif_model_completion_batch_id: ...)
      # clause: NOT IN mishandles the NULL batch ids most completions have.
      def active_batch_members
        Raif::ModelCompletion.where(
          raif_model_completion_batch_id: Raif::ModelCompletionBatch.non_terminal.select(:id)
        )
      end

      def completions_with_cost_event
        Raif::InferenceCostEvent.where.not(raif_model_completion_id: nil).select(:raif_model_completion_id)
      end

      def terminal_without_cost_event(cutoff)
        terminal_scope(cutoff).where.not(id: completions_with_cost_event)
      end

      # Completions with citations whose Raif::ConversationEntry source has
      # an empty local citations column: culling them would erase citation
      # chips from historical conversations.
      def completions_with_uncopied_citations
        completion_citations_length = json_array_length_sql("raif_model_completions.citations")
        entry_citations_length = json_array_length_sql("raif_conversation_entries.citations")

        Raif::ModelCompletion
          .where(source_type: "Raif::ConversationEntry")
          .joins("INNER JOIN raif_conversation_entries ON raif_conversation_entries.id = raif_model_completions.source_id")
          .where("raif_model_completions.citations IS NOT NULL AND #{completion_citations_length} > 0")
          .where("raif_conversation_entries.citations IS NULL OR #{entry_citations_length} = 0")
      end

      # Table-qualified equivalent of
      # Raif::ApplicationRecord.where_json_not_blank, which can't be used
      # inside the entries join above (both tables have a citations column).
      def json_array_length_sql(qualified_column)
        case Raif::ModelCompletion.connection.adapter_name.downcase
        when "postgresql"
          "jsonb_array_length(#{qualified_column})"
        when "mysql2", "trilogy"
          "JSON_LENGTH(#{qualified_column})"
        else
          raise "Unsupported database: #{Raif::ModelCompletion.connection.adapter_name}"
        end
      end
    end

    def perform(max_batches: 4)
      return unless Raif.config.archive_enabled
      return if Raif.config.archive_storage.nil?
      return if Raif.config.model_completion_retention_period.nil?

      # Defense in depth: Raif::Configuration#validate! enforces this floor
      # at boot, but a destructive job must not trust that validation ran
      # (initializers can be skipped or misordered on a misconfigured node).
      # Cost/budget consumers aggregate by billing period, so a tiny
      # retention value must never be able to cull inside an open window.
      if Raif.config.model_completion_retention_period < 1.month
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.model_completion_retention_period must be at least 1 month (got #{Raif.config.model_completion_retention_period.inspect})"
      end

      with_advisory_lock do
        # Frozen at job start so every batch in this run shares one cutoff.
        cutoff = Raif.config.model_completion_retention_period.ago

        max_batches.times do
          ids = self.class.eligible_scope(cutoff).order(:id).limit(BATCH_RECORD_LIMIT).pluck(:id)
          break if ids.empty?

          archive_batch!(ids, cutoff)
        end
      end
    end

  private

    # ids is a plain in-memory array; nothing about the batch is persisted
    # until the upload has succeeded. Everything downstream of serialization
    # (key, audit row, stamping, deletion) targets the ids the serializer
    # ACTUALLY wrote: the byte cap can close a batch early, and rows can
    # vanish between pluck and serialize - anything not written stays
    # eligible and re-enters a later batch.
    def archive_batch!(ids, cutoff)
      serialized = Raif::ArchiveSerializer.new(
        relation: Raif::ModelCompletion.where(id: ids),
        cutoff_at: cutoff,
        byte_limit: BATCH_UNCOMPRESSED_BYTE_LIMIT
      ).serialize

      begin
        archived_ids = serialized[:record_ids]
        return if archived_ids.empty?

        # The 122 bits of run-suffix randomness make key reuse effectively
        # impossible: a re-run after a crash writes a fresh object instead of
        # resuming or overwriting (a collision would silently overwrite a
        # prior archive object whose rows were already deleted, before the DB
        # unique-key check could fire).
        key = "#{KEY_PREFIX}/#{archived_ids.first}-#{archived_ids.last}-#{Time.current.utc.strftime("%Y%m%dT%H%M%SZ")}-#{SecureRandom.uuid}.jsonl.gz"

        # Raises on failure -> the run aborts and zero rows are deleted.
        location = File.open(serialized[:path], "rb") do |io|
          Raif.config.archive_storage.write(key: key, io: io, checksum_sha256: serialized[:checksum_sha256])
        end

        # Row exists = object uploaded; created in the same run that deletes.
        archive = Raif::Archive.create!(
          resource_type: "Raif::ModelCompletion",
          key: key,
          location: location,
          cutoff_at: cutoff,
          first_record_id: archived_ids.first,
          last_record_id: archived_ids.last,
          record_count: archived_ids.size,
          compressed_bytes: serialized[:compressed_bytes],
          checksum_sha256: serialized[:checksum_sha256]
        )

        # Re-check eligibility at delete time: the upload window can be long
        # (a large PUT), and a row mutated during it (touched, cost event
        # removed, pulled into a live batch) must survive - its uploaded copy
        # is stale. The survivor stays eligible and re-enters a later batch
        # once quiescent again; its copy in this object is just the accepted
        # harmless duplicate.
        deletable_ids = self.class.eligible_scope(cutoff).where(id: archived_ids).pluck(:id)

        # Stamp the archive link on the durable cost records BEFORE deletion:
        # the FK is nullified at the DB level the moment the completion row
        # is deleted. Only deletable rows are stamped, so the stamp always
        # means "culled into this archive". Idempotent update_all, so a
        # crash-then-re-run is safe.
        Raif::InferenceCostEvent
          .where(raif_model_completion_id: deletable_ids)
          .update_all(raif_archive_id: archive.id)

        # DB-level ON DELETE SET NULL handles the cost event FK;
        # original_model_completion_id retains record identity.
        Raif::ModelCompletion.where(id: deletable_ids).in_batches(of: 5_000).delete_all
      ensure
        File.unlink(serialized[:path]) if File.exist?(serialized[:path])
      end
    end

    # Session-level, non-blocking: a second concurrent perform returns
    # immediately. PG and MySQL adapters both implement get_advisory_lock;
    # for anything else, proceed unguarded (hosts control scheduling anyway).
    def with_advisory_lock(&block)
      connection = Raif::ModelCompletion.connection
      return yield unless connection.respond_to?(:get_advisory_lock)

      # Stable across processes (String#hash is per-process salted) and
      # within PG's signed bigint range.
      lock_id = Digest::SHA256.hexdigest(ADVISORY_LOCK_NAME)[0, 15].to_i(16)
      return unless connection.get_advisory_lock(lock_id)

      begin
        yield
      ensure
        connection.release_advisory_lock(lock_id)
      end
    end
  end
end
