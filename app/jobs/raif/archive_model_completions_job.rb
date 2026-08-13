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
  # encryption, lifecycle rules) must therefore apply to whole prefixes
  # (the unpartitioned KEY_PREFIX and, with partitioning, every prefix
  # under raif-archives/partitions/), never be derived from raif_archives
  # rows. Prefix-wide coverage is also what makes
  # Raif::Archive.purge_partition! complete: it erases a partition's whole
  # prefix, crash-orphaned objects included.
  #
  # Inert unless the host explicitly opts in: archive_enabled must be true
  # AND an archive_storage adapter must be configured AND a retention period
  # must be set, otherwise perform returns without touching anything.
  #
  # Hosts own scheduling (raif's usual convention, like
  # Raif::ExpireStuckModelCompletionBatchesJob): run it e.g. nightly. Three
  # budgets bound the work per run (max_records, max_objects, max_runtime);
  # the same code drains a multi-year backlog gradually and handles steady
  # state. Concurrent runs are excluded via an advisory lock. Before
  # enabling, operators can preview with
  # Raif::ArchiveModelCompletionsJob.dry_run.
  #
  # With Raif.config.archive_partition_column set, every archive object
  # holds records from exactly one partition and is stored under that
  # partition's key prefix (see Raif::ArchivePartition), the layout that
  # makes complete per-partition erasure possible. Work is scheduled in
  # round-robin passes, at most one object per partition per pass, visiting
  # eligible partitions ordered by their oldest eligible completion: many
  # small partitions drain within a run while one large-backlog partition
  # cannot monopolize it. Records whose partition value is NULL (or
  # normalizes to blank) fail closed, ineligible until the host either
  # attributes them or opts into the Raif::Archive::UNGROUPED fallback.
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

    # Key prefix when partitioning is unset.
    KEY_PREFIX = "raif-archives/model-completions"
    # Resource segment below a partition prefix:
    # raif-archives/partitions/<token>/model-completions/<object>
    RESOURCE_KEY_SEGMENT = "model-completions"
    # Distinct partitions fetched per round-robin pass. The listing query is
    # a GROUP BY over the full multi-guard eligibility scope, the one
    # potentially expensive query in the fairness design, so it is capped.
    # Partitions beyond the cap are reached in later passes: archiving a
    # partition's oldest records pushes it down the oldest-first ordering.
    PARTITIONS_PER_PASS = 100

    # Internal control-flow signal: a serialized record's partition value
    # changed during the upload window, so this cull must abort and the
    # uploaded object is tainted.
    class TaintedPartitionError < StandardError; end
    private_constant :TaintedPartitionError

    class << self
      # A completion is safe to archive and delete only when ALL hold:
      #
      # - created_at is before the (job-frozen) retention cutoff
      # - it has been quiescent: not updated within QUIESCENCE_PERIOD
      # - it is not a member of a model completion batch that is still
      #   non-terminal (belt-and-suspenders alongside quiescence)
      # - durability guard, TERMINAL rows only: its Raif::InferenceCostEvent
      #   exists AND is at least as fresh as the completion
      #   (event.updated_at >= completion.updated_at). A post-terminal update
      #   whose event re-sync failed leaves a stale event that missing-only
      #   repair would never revisit, so the repair job also re-syncs stale
      #   events; until then the row just waits.
      # - nonterminal rows skip the durability guard: they never reached a
      #   terminal state, so no cost event exists and there is no spend to
      #   protect. These are orphaned pending rows from killed processes and
      #   crashed jobs (a third of one host's table in practice) that would
      #   otherwise be immortal. They are archived through the same path as
      #   everything else - NOT deleted outright, despite the temptation (no
      #   response, near-zero historical value): "every deleted completion
      #   exists in an archive" must hold without exception, and a
      #   delete-without-archive shortcut would be a second deletion
      #   semantics that weakens the invariant this job's safety rests on,
      #   to save pennies of mostly-redundant prompt storage.
      # - durable-citations guard: its citations, if any, have been copied to
      #   its Raif::ConversationEntry source (protects hosts that haven't run
      #   the conversation entry backfill)
      def eligible_scope(cutoff)
        base_scope(cutoff)
          .where(completions_table[:updated_at].lt(QUIESCENCE_PERIOD.ago))
          .where.not(id: active_batch_members)
          .where.not(id: terminal_without_fresh_cost_event(cutoff))
          .where.not(id: completions_with_uncopied_citations)
      end

      # Counts what a run under the given cutoff would archive (split by
      # terminal state), plus the per-guard exclusions among cutoff-aged
      # completions. Writes nothing; re-runnable anytime. Operators run this
      # before enabling archiving (defaults to the configured retention
      # period so it can be previewed while archive_enabled is still false).
      def dry_run(cutoff: Raif.config.model_completion_retention_period&.ago)
        raise ArgumentError, "Provide a cutoff: or set Raif.config.model_completion_retention_period" if cutoff.nil?

        validate_partition_column!

        eligible = eligible_scope(cutoff)

        result = {
          cutoff: cutoff,
          eligible: eligible.count,
          eligible_terminal: eligible.where("completed_at IS NOT NULL OR failed_at IS NOT NULL").count,
          eligible_nonterminal: eligible.where(completed_at: nil, failed_at: nil).count,
          excluded_by_quiescence: base_scope(cutoff).where(completions_table[:updated_at].gteq(QUIESCENCE_PERIOD.ago)).count,
          excluded_by_active_batch: base_scope(cutoff).where(id: active_batch_members).count,
          excluded_missing_cost_event: terminal_scope(cutoff).where.not(id: completions_with_cost_event).count,
          excluded_stale_cost_event: terminal_scope(cutoff)
            .where(id: completions_with_cost_event)
            .where.not(id: completions_with_fresh_cost_event).count,
          excluded_uncopied_citations: base_scope(cutoff).where(id: completions_with_uncopied_citations).count
        }

        add_partition_report!(result, eligible)
        result
      end

      def partition_column
        Raif.config.archive_partition_column
      end

      def ungrouped_fallback?
        Raif.config.archive_partition_fallback.equal?(Raif::Archive::UNGROUPED)
      end

      # Column existence is validated here, at job/dry_run execution time,
      # never at boot: Raif::Configuration#validate! is deliberately DB-free
      # so blank-database boots (db:create, db:migrate, asset precompile)
      # keep working. Each archived resource's job validates the column on
      # its own resource.
      def validate_partition_column!
        return if partition_column.nil?
        return if Raif::ModelCompletion.column_names.include?(partition_column.to_s)

        raise Raif::Errors::InvalidConfigError,
          "Raif.config.archive_partition_column is :#{partition_column}, but #{Raif::ModelCompletion.table_name} " \
            "has no #{partition_column} column"
      end

    private

      # Per-partition eligible counts plus the fail-closed
      # excluded_by_missing_partition count. Group values are normalized in
      # Ruby (via to_s, like Raif::ArchivePartition) so blank detection
      # matches archival exactly; the report keys real partitions by their
      # normalized value and the ungrouped partition (fallback opt-in only)
      # by nil, mirroring its NULL partition_value on Raif::Archive rows.
      def add_partition_report!(result, eligible)
        col = partition_column
        return if col.nil?

        partitions = {}
        missing = { eligible_terminal: 0, eligible_nonterminal: 0 }

        {
          eligible_terminal: eligible.where("completed_at IS NOT NULL OR failed_at IS NOT NULL").group(col).count,
          eligible_nonterminal: eligible.where(completed_at: nil, failed_at: nil).group(col).count
        }.each do |kind, counts|
          counts.each do |raw, count|
            if raw.to_s.blank? && !ungrouped_fallback?
              missing[kind] += count
            else
              key = raw.to_s.blank? ? nil : raw.to_s
              partitions[key] ||= { eligible_terminal: 0, eligible_nonterminal: 0 }
              partitions[key][kind] += count
            end
          end
        end

        result[:excluded_by_missing_partition] = missing.values.sum
        result[:partitions] = partitions

        # Missing-partition records are retained (never archived), so the
        # headline eligible counts exclude them.
        result[:eligible] -= missing.values.sum
        result[:eligible_terminal] -= missing[:eligible_terminal]
        result[:eligible_nonterminal] -= missing[:eligible_nonterminal]
      end

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

      # Events at least as fresh as their completion. An older event means a
      # post-terminal completion update committed but its event re-sync
      # failed: the durable spend data may be stale, so the row is not safe
      # to cull until the repair job re-syncs (or freshness-certifies) it.
      def completions_with_fresh_cost_event
        Raif::InferenceCostEvent
          .joins("INNER JOIN raif_model_completions ON raif_model_completions.id = raif_inference_cost_events.raif_model_completion_id")
          .where("raif_inference_cost_events.updated_at >= raif_model_completions.updated_at")
          .select(:raif_model_completion_id)
      end

      def terminal_without_fresh_cost_event(cutoff)
        terminal_scope(cutoff).where.not(id: completions_with_fresh_cost_event)
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

    def perform(max_records: 100_000, max_objects: 500, max_runtime: 30.minutes)
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

      self.class.validate_partition_column!

      # Shared with Raif::Archive.purge_partition!; a second concurrent
      # perform (or a purge in progress) makes this run return immediately.
      Raif::ArchiveAdvisoryLock.acquire do
        # Frozen at job start so every batch in this run shares one cutoff.
        cutoff = Raif.config.model_completion_retention_period.ago
        deadline = monotonic_now + max_runtime.to_f
        records_remaining = max_records
        objects_remaining = max_objects

        # Round-robin passes: at most one object per partition per pass, so
        # many small partitions all drain within a run while one
        # large-backlog partition cannot monopolize it. With partitioning
        # unset there is exactly one pseudo-partition and this reduces to
        # sequential batching. The runtime budget is only checked between
        # objects: a started object always finishes, so a run always stops
        # in a safe state.
        loop do
          culled_any = false

          partition_selections(cutoff).each do |partition, predicate|
            break if records_remaining <= 0 || objects_remaining <= 0 || monotonic_now >= deadline

            ids = eligible_batch_ids(cutoff, partition, predicate, limit: [BATCH_RECORD_LIMIT, records_remaining].min)
            next if ids.empty?

            outcome = archive_batch!(ids, cutoff, partition: partition, partition_predicate: predicate)
            next if outcome.nil?

            records_remaining -= outcome[:records]
            objects_remaining -= 1
            # A tainted batch (partition mutated during upload, object
            # cleaned up) spends budget but is not progress: without a
            # successful cull somewhere, another pass could only repeat the
            # same work.
            culled_any ||= outcome[:culled]
          end

          break unless culled_any
          break if records_remaining <= 0 || objects_remaining <= 0 || monotonic_now >= deadline
        end
      end
    end

  private

    # Eligible partitions for one pass, ordered by each partition's oldest
    # eligible completion and capped at PARTITIONS_PER_PASS. Returns
    # [partition, predicate] pairs, where the predicate re-selects the
    # partition's records; [[nil, nil]] when partitioning is unset. Group
    # values that normalize to blank fail closed (skipped) unless the host
    # explicitly opted into the ungrouped fallback, in which case they merge
    # into one reserved ungrouped partition at the position of its oldest
    # member.
    def partition_selections(cutoff)
      col = self.class.partition_column
      return [[nil, nil]] if col.nil?

      raws = self.class.eligible_scope(cutoff)
        .group(col)
        .order(Arel.sql("MIN(#{Raif::ModelCompletion.table_name}.created_at) ASC"))
        .limit(PARTITIONS_PER_PASS)
        .pluck(col)

      selections = []
      ungrouped_values = []

      raws.each do |raw|
        if raw.to_s.blank?
          selections << :ungrouped if ungrouped_values.empty? && self.class.ungrouped_fallback?
          ungrouped_values << raw
        else
          selections << [Raif::ArchivePartition.for(raw), { col => raw }]
        end
      end

      selections.map do |selection|
        selection == :ungrouped ? [Raif::ArchivePartition.ungrouped, { col => ungrouped_values }] : selection
      end
    end

    def eligible_batch_ids(cutoff, partition, predicate, limit:)
      scope = self.class.eligible_scope(cutoff)
      scope = scope.where(predicate) if predicate
      scope = scope.order(:id).limit(limit)
      return scope.pluck(:id) if partition.nil?

      # Fail closed on normalization mismatches: SQL equality can be looser
      # than the normalized string comparison (e.g. case-insensitive
      # collations), and a record archived under a prefix its own normalized
      # value does not hash to would be invisible to its partition's purge.
      rows = scope.pluck(:id, self.class.partition_column)
      matching = rows.select { |_id, raw| partition_matches?(partition, raw) }

      # Dropped rows are retained indefinitely while dry_run still counts
      # them eligible, so the skip must not be silent.
      if matching.size < rows.size
        Rails.logger.warn(
          "Raif::ArchiveModelCompletionsJob: #{rows.size - matching.size} record(s) matched partition " \
            "#{partition.token} by SQL equality but not by normalized value (e.g. a case-insensitive collation " \
            "matching a mixed-case variant); they fail closed and were skipped"
        )
      end

      matching.map(&:first)
    end

    def partition_matches?(partition, raw)
      partition.ungrouped? ? raw.to_s.blank? : raw.to_s == partition.value
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # ids is a plain in-memory array; nothing about the batch is persisted
    # until the upload has succeeded. Everything downstream of serialization
    # (key, audit row, stamping, deletion) targets the ids the serializer
    # ACTUALLY wrote: the byte cap can close a batch early, and rows can
    # vanish between pluck and serialize - anything not written stays
    # eligible and re-enters a later batch.
    #
    # Returns nil when nothing was serialized, otherwise
    # { records: <count uploaded>, culled: <false when the cull aborted on a
    # tainted partition> } so the caller can spend budgets and track
    # progress.
    def archive_batch!(ids, cutoff, partition:, partition_predicate:)
      serialized = Raif::ArchiveSerializer.new(
        relation: Raif::ModelCompletion.where(id: ids),
        cutoff_at: cutoff,
        byte_limit: BATCH_UNCOMPRESSED_BYTE_LIMIT,
        partition_column: partition && self.class.partition_column,
        partition_value: partition&.value
      ).serialize

      begin
        archived_ids = serialized[:record_ids]
        return nil if archived_ids.empty?

        key = build_key(partition, archived_ids)

        # Raises on failure -> the run aborts and zero rows are deleted.
        location = File.open(serialized[:path], "rb") do |io|
          Raif.config.archive_storage.write(key: key, io: io, checksum_sha256: serialized[:checksum_sha256])
        end

        # The write contract's proof of upload is "returned a location
        # string without raising". A blank or non-string return means the
        # adapter did not honor the contract (an easy mistake in a custom
        # adapter - an accidental implicit nil return), so nothing below may
        # trust that an object exists.
        unless location.is_a?(String) && location.present?
          raise Raif::Errors::ArchiveStorageError,
            "Raif.config.archive_storage.write must return a nonblank location string (got #{location.inspect}); " \
              "refusing to record the archive or delete any rows"
        end

        # Row exists = object uploaded; created in the same run that deletes.
        archive = Raif::Archive.create!(
          resource_type: "Raif::ModelCompletion",
          key: key,
          location: location,
          cutoff_at: cutoff,
          partition_value: partition&.value,
          first_record_id: archived_ids.first,
          last_record_id: archived_ids.last,
          record_count: archived_ids.size,
          compressed_bytes: serialized[:compressed_bytes],
          checksum_sha256: serialized[:checksum_sha256]
        )

        culled = cull_archived_rows!(archive, archived_ids, cutoff, partition, partition_predicate)

        { records: archived_ids.size, culled: culled }
      ensure
        File.unlink(serialized[:path]) if File.exist?(serialized[:path])
      end
    end

    # Final cull, atomic: re-select the serialized ids through the full
    # eligibility scope (and, when partitioning, the partition predicate)
    # with row locks, stamp, and delete in one transaction. The re-check
    # exists because the upload window can be long: a row mutated during it
    # must survive (its uploaded copy is stale) and re-enters a later batch
    # once quiescent again. The locks close the residual race between this
    # selection and the delete (e.g. a row terminalizing in that gap would
    # be deleted with an unstamped cost event). On failure, stamps and
    # deletes roll back together; the Archive row stays outside the
    # transaction because it records the upload, not the cull, and the
    # uploaded object remains the accepted harmless duplicate. The one
    # exception is a tainted partition (a record's partition value changed
    # during upload): the whole cull aborts and the object and row are
    # removed, because that object misfiles a record under a prefix its
    # partition's purge could never find.
    def cull_archived_rows!(archive, archived_ids, cutoff, partition, partition_predicate)
      Raif::ModelCompletion.transaction do
        assert_partition_unchanged!(archived_ids, partition) if partition

        deletable_scope = self.class.eligible_scope(cutoff).where(id: archived_ids)
        deletable_scope = deletable_scope.where(partition_predicate) if partition_predicate
        deletable = deletable_scope.order(:id).lock.pluck(:id, :completed_at, :failed_at)
        deletable_ids = deletable.map(&:first)
        terminal_ids = deletable.filter_map { |id, completed_at, failed_at| id if completed_at || failed_at }

        # Stamp the archive link on the durable cost records BEFORE
        # deletion: the FK is nullified at the DB level the moment the
        # completion row is deleted. Terminal rows only (nonterminal rows
        # have no events), and only deletable ones, so the stamp always
        # means "culled into this archive".
        stamped_count = Raif::InferenceCostEvent
          .where(raif_model_completion_id: terminal_ids)
          .update_all(raif_archive_id: archive.id)

        # The locks above cover the completion rows, not their events: an
        # event deleted between the selection and the stamp would let a
        # terminal completion be culled without its durable spend record.
        # The stamped count proves every terminal row carries its stamp
        # into deletion; a mismatch rolls back stamps and deletes together.
        if stamped_count != terminal_ids.size
          raise "Raif::ArchiveModelCompletionsJob: expected to stamp #{terminal_ids.size} cost event(s) for " \
            "archive ##{archive.id} but stamped #{stamped_count}; a cost event vanished between eligibility " \
            "selection and stamping - rolling back this cull"
        end

        # original_model_completion_id retains record identity after the
        # delete nullifies the events' completion FK.
        Raif::ModelCompletion.where(id: deletable_ids).in_batches(of: 5_000).delete_all
      end

      true
    rescue TaintedPartitionError
      cleanup_tainted_archive!(archive)
      false
    end

    # Locks every serialized row and verifies its partition value still
    # normalizes to this batch's partition. A record whose partition changed
    # during the upload window must not be culled: its uploaded copy sits
    # under the OLD partition's prefix, where the new partition's purge
    # could never find it. Locking here, before the eligibility recheck,
    # pins the values until commit.
    def assert_partition_unchanged!(archived_ids, partition)
      rows = Raif::ModelCompletion.where(id: archived_ids).order(:id).lock.pluck(:id, self.class.partition_column)
      return if rows.all? { |_id, raw| partition_matches?(partition, raw) }

      raise TaintedPartitionError
    end

    # Best-effort removal of the tainted object and its audit row (the cull
    # already rolled back; the rows survive and re-enter later batches under
    # their current partitions). The row is destroyed only after the object
    # deletion succeeded, preserving "row exists = object uploaded". This
    # cleanup cannot close every crash window, which is why the partition
    # column's immutability remains a hard host contract.
    def cleanup_tainted_archive!(archive)
      Rails.logger.warn(
        "Raif::ArchiveModelCompletionsJob: a record's #{self.class.partition_column} value changed during the " \
          "upload of #{archive.key}; aborted the cull and removing the tainted object. " \
          "Raif.config.archive_partition_column must be immutable for a record's lifetime."
      )

      storage = Raif.config.archive_storage
      unless storage.respond_to?(:delete)
        Rails.logger.error(
          "Raif::ArchiveModelCompletionsJob: cannot remove tainted object #{archive.key}: the archive_storage " \
            "adapter does not implement delete(key:); leaving the object and its Raif::Archive row in place"
        )
        return
      end

      storage.delete(key: archive.key)
      archive.destroy!
    rescue Raif::Errors::ArchiveStorageError => e
      Rails.logger.error(
        "Raif::ArchiveModelCompletionsJob: failed to remove tainted object #{archive.key} " \
          "(#{e.message}); leaving its Raif::Archive row in place"
      )
    end

    def build_key(partition, archived_ids)
      prefix = partition ? "#{partition.storage_prefix}#{RESOURCE_KEY_SEGMENT}" : KEY_PREFIX

      # The 122 bits of run-suffix randomness make key reuse effectively
      # impossible: a re-run after a crash writes a fresh object instead of
      # resuming or overwriting (a collision would silently overwrite a
      # prior archive object whose rows were already deleted, before the DB
      # unique-key check could fire).
      "#{prefix}/#{archived_ids.first}-#{archived_ids.last}-#{Time.current.utc.strftime("%Y%m%dT%H%M%SZ")}-#{SecureRandom.uuid}.jsonl.gz"
    end

  end
end
