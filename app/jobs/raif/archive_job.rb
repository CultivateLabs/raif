# frozen_string_literal: true

module Raif
  # Abstract base for the archive-and-cull jobs. Subclasses (see
  # Raif::ArchiveModelCompletionsJob, Raif::ArchiveTasksJob) name the resource
  # and its eligibility rules; everything below - batching, partition
  # fairness, upload, the tainted-partition abort and the cull transaction -
  # is shared, so the safety invariants have exactly one implementation.
  # Enabling, scheduling, storage requirements and partitioning are documented
  # for operators at https://docs.raif.ai/learn_more/archiving.
  #
  # The invariants this job exists to hold:
  #
  # - At-least-once archiving + never-delete-unarchived. A batch is deleted
  #   only after this run uploaded it, and a re-run after any crash writes a
  #   new object under a new key rather than resuming or overwriting. There
  #   is no persisted in-flight state to repair, ever.
  # - The accepted cost of that is duplicate objects: a crash between the
  #   upload and the Raif::Archive insert leaves an object that no row references
  #   (those rows were not deleted, so they re-archive next run). Storage
  #   policy must therefore apply to whole prefixes and never be derived
  #   from raif_archives rows, which is also what makes
  #   Raif::Archive.purge_partition! complete.
  # - Inert unless the host opts in: archive_enabled, an archive_storage
  #   adapter and a retention period must all be set, or perform returns
  #   without touching anything.
  # - With partitioning, every object holds records from exactly one
  #   partition (see Raif::ArchivePartition). Per-partition erasure rests on
  #   that, so a record whose partition changes mid-upload taints the object
  #   and aborts the cull.
  #
  # Subclasses implement the "Subclass contract" class methods below and the
  # stamp_cost_events! hook; the dependent-resource hooks are optional.
  class ArchiveJob < ApplicationJob
    # Caps are constants, not config: public config is API; add a knob only
    # when a host demonstrably needs it. Read through self, so a subclass can
    # override one. A batch closes when EITHER cap is hit; the byte cap keeps
    # wildly varying payloads (agent message arrays can be enormous) from
    # building a multi-GB tempfile.
    BATCH_RECORD_LIMIT = 25_000
    BATCH_UNCOMPRESSED_BYTE_LIMIT = 512.megabytes
    # Rows updated more recently than this are ineligible for archiving,
    # regardless of age.
    QUIESCENCE_PERIOD = 24.hours
    # Distinct partitions fetched per round-robin pass. The listing query is
    # a GROUP BY over the full multi-guard eligibility scope, the one
    # potentially expensive query in the fairness design, so it is capped.
    PARTITIONS_PER_PASS = 100

    # Internal control-flow signal: a serialized record's partition value
    # changed during the upload window, so this cull must abort and the
    # uploaded object is tainted.
    class TaintedPartitionError < StandardError; end
    private_constant :TaintedPartitionError

    class << self
      # ---- Subclass contract ----

      # The archived ActiveRecord class. Must expose created_at, updated_at,
      # completed_at and failed_at: the terminal/nonterminal split runs in
      # shared code.
      def archived_class
        raise NotImplementedError, "#{name} must implement .archived_class"
      end

      # The configured retention duration, or nil to keep this resource
      # forever. Read fresh on every call: hosts reconfigure at boot.
      def retention_period
        raise NotImplementedError, "#{name} must implement .retention_period"
      end

      # The Raif.config accessor behind retention_period, for error messages.
      def retention_config_name
        raise NotImplementedError, "#{name} must implement .retention_config_name"
      end

      # Key prefix when partitioning is unset.
      def key_prefix
        raise NotImplementedError, "#{name} must implement .key_prefix"
      end

      # Resource segment below a partition prefix:
      # raif-archives/partitions/<token>/<segment>/<object>
      def resource_key_segment
        raise NotImplementedError, "#{name} must implement .resource_key_segment"
      end

      # Every guard that makes a record safe to archive AND delete. Called on
      # every pass, and again under row locks inside the cull transaction, so
      # it must be a pure relation with no side effects.
      def eligible_scope(_cutoff)
        raise NotImplementedError, "#{name} must implement .eligible_scope"
      end

      # Per-guard exclusion counts for dry_run, as a Hash. Optional.
      def dry_run_exclusions(_cutoff)
        {}
      end

      # ---- Shared ----

      # Counts what a run under the given cutoff would archive (split by
      # terminal state), plus the subclass's per-guard exclusions among
      # cutoff-aged records. Writes nothing; re-runnable anytime. Operators
      # run this before enabling archiving (it defaults to the configured
      # retention period so it can be previewed while archive_enabled is
      # still false).
      def dry_run(cutoff: retention_period&.ago)
        raise ArgumentError, "Provide a cutoff: or set Raif.config.#{retention_config_name}" if cutoff.nil?

        validate_partition_column!

        eligible = eligible_scope(cutoff)

        result = {
          cutoff: cutoff,
          eligible: eligible.count,
          eligible_terminal: eligible.where("completed_at IS NOT NULL OR failed_at IS NOT NULL").count,
          eligible_nonterminal: eligible.where(completed_at: nil, failed_at: nil).count,
          excluded_by_quiescence: base_scope(cutoff).where(resource_table[:updated_at].gteq(self::QUIESCENCE_PERIOD.ago)).count
        }.merge(dry_run_exclusions(cutoff))

        add_partition_report!(result, eligible)
        result
      end

      def partition_column
        Raif.config.archive_partition_column
      end

      def ungrouped_fallback?
        Raif.config.archive_partition_fallback.equal?(Raif::ArchivePartition::UNGROUPED)
      end

      # Column existence is validated here, at job/dry_run execution time,
      # never at boot: Raif::Configuration#validate! is deliberately DB-free
      # so blank-database boots (db:create, db:migrate, asset precompile)
      # keep working. Each archived resource's job validates the column on
      # its own resource.
      def validate_partition_column!
        return if partition_column.nil?
        return if archived_class.column_names.include?(partition_column.to_s)

        raise Raif::Errors::InvalidConfigError,
          "Raif.config.archive_partition_column is :#{partition_column}, but #{archived_class.table_name} " \
            "has no #{partition_column} column"
      end

      def base_scope(cutoff)
        archived_class.where(resource_table[:created_at].lt(cutoff))
      end

      def terminal_scope(cutoff)
        base_scope(cutoff).where("completed_at IS NOT NULL OR failed_at IS NOT NULL")
      end

      def quiescent_scope(cutoff)
        base_scope(cutoff).where(resource_table[:updated_at].lt(self::QUIESCENCE_PERIOD.ago))
      end

      def resource_table
        archived_class.arel_table
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
    end

    def perform(max_records: 100_000, max_objects: 500, max_runtime: 30.minutes)
      return unless Raif.config.archive_enabled
      return if Raif.config.archive_storage.nil?

      retention_period = self.class.retention_period
      return if retention_period.nil?

      # Defense in depth: Raif::Configuration#validate! enforces this floor
      # at boot, but a destructive job must not trust that validation ran
      # (initializers can be skipped or misordered on a misconfigured node).
      # Cost/budget consumers aggregate by billing period, so a tiny
      # retention value must never be able to cull inside an open window.
      if retention_period < 1.month
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.#{self.class.retention_config_name} must be at least 1 month (got #{retention_period.inspect})"
      end

      self.class.validate_partition_column!

      # Shared with Raif::Archive.purge_partition! and with every other
      # archive job; a second concurrent perform (or a purge in progress)
      # makes this run return immediately.
      Raif::ArchiveAdvisoryLock.acquire do
        # Frozen at job start so every batch in this run shares one cutoff.
        cutoff = retention_period.ago
        deadline = monotonic_now + max_runtime.to_f
        records_remaining = max_records
        objects_remaining = max_objects

        # Round-robin passes: at most one object per partition per pass, so
        # many small partitions all drain within a run while one
        # large-backlog partition cannot monopolize it. Each pass excludes
        # the partitions already visited this round, paging through EVERY
        # eligible partition before any is revisited (the listing cap alone
        # would relist the same oldest cohort while it still holds the
        # oldest rows, starving partitions beyond the cap). A pass that
        # lists nothing ends the round; a new round starts only if the
        # finished round culled something. With partitioning unset there is
        # exactly one pseudo-partition and this reduces to sequential
        # batching. The runtime budget is only checked between objects: a
        # started object always finishes, so a run always stops in a safe
        # state.
        visited = []
        round_culled = false

        loop do
          selections = partition_selections(cutoff, visited)

          if selections.empty?
            break unless round_culled

            visited = []
            round_culled = false
            next
          end

          selections.each do |partition, predicate, raws|
            break if records_remaining <= 0 || objects_remaining <= 0 || monotonic_now >= deadline

            # Marked visited even when nothing archives, or an emptied
            # partition would relist in every pass for the rest of the round.
            visited.concat(raws)

            ids = eligible_batch_ids(cutoff, partition, predicate, limit: [self.class::BATCH_RECORD_LIMIT, records_remaining].min)
            next if ids.empty?

            outcome = archive_batch!(ids, cutoff, partition: partition, partition_predicate: predicate)
            next if outcome.nil?

            records_remaining -= outcome[:records]
            objects_remaining -= 1
            # A tainted batch (partition mutated during upload, object
            # cleaned up) spends budget but is not progress; the round
            # moves on to other partitions.
            round_culled ||= outcome[:culled]
          end

          break if records_remaining <= 0 || objects_remaining <= 0 || monotonic_now >= deadline
        end
      end
    end

  private

    # ---- Subclass hooks ----

    # Links the durable cost records to this archive, inside the cull
    # transaction and immediately before the rows are deleted. terminal_ids
    # are the ids about to be deleted that reached a terminal state. Raise to
    # roll the whole cull back.
    def stamp_cost_events!(_archive, _terminal_ids)
      raise NotImplementedError, "#{self.class.name} must implement #stamp_cost_events!"
    end

    # Uploads any dependent-resource objects for this batch, BEFORE the cull
    # transaction opens (uploads are long and must never hold row locks).
    # Returns the Raif::Archive rows created, which are cleaned up alongside
    # the primary archive when the cull aborts on a tainted partition.
    def archive_dependents!(_archived_ids, _cutoff, _partition)
      []
    end

    # Deletes the dependent rows belonging to the culled records, inside the
    # cull transaction and before the primary rows are deleted.
    def delete_dependents!(_deletable_ids); end

    # ---- Shared ----

    # Eligible partitions for one pass, ordered by each partition's oldest
    # eligible record, capped at PARTITIONS_PER_PASS, and excluding the
    # partitions already visited this round. Returns [partition, predicate, raws]
    # triples: the predicate re-selects the partition's records and raws are
    # the group values the caller marks visited. [[nil, nil, [:unpartitioned]]]
    # when partitioning is unset (a single pseudo-partition). Group values
    # that normalize to blank fail closed (NULLs excluded in SQL, other
    # blank-normalizing values skipped) unless the host explicitly opted
    # into the ungrouped fallback, in which case they merge into one
    # reserved ungrouped partition at the position of its oldest member.
    def partition_selections(cutoff, visited)
      col = self.class.partition_column
      return visited.empty? ? [[nil, nil, [:unpartitioned]]] : [] if col.nil?

      table = self.class.resource_table
      scope = self.class.eligible_scope(cutoff)
      # Fail-closed NULLs never archive; keeping them out of the listing
      # stops them occupying a slot in every pass.
      scope = scope.where(table[col].not_eq(nil)) unless self.class.ungrouped_fallback?

      visited_values = visited.compact
      if visited_values.any?
        # NOT IN alone would also drop the NULL group (NULL never matches
        # NOT IN), so NULLs are kept explicitly.
        scope = scope.where(table[col].not_in(visited_values).or(table[col].eq(nil)))
      end
      scope = scope.where(table[col].not_eq(nil)) if visited.include?(nil)

      raws = scope
        .group(col)
        .order(Arel.sql("MIN(#{self.class.archived_class.table_name}.created_at) ASC"))
        .limit(self.class::PARTITIONS_PER_PASS)
        .pluck(col)

      selections = []
      ungrouped_values = []

      raws.each do |raw|
        if raw.to_s.blank?
          selections << :ungrouped if ungrouped_values.empty? && self.class.ungrouped_fallback?
          ungrouped_values << raw
        else
          selections << [Raif::ArchivePartition.for(raw), { col => raw }, [raw]]
        end
      end

      selections.map do |selection|
        if selection == :ungrouped
          [Raif::ArchivePartition.ungrouped, { col => ungrouped_values }, ungrouped_values]
        else
          selection
        end
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
          "#{self.class.name}: #{rows.size - matching.size} record(s) matched partition " \
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
        relation: self.class.archived_class.where(id: ids),
        cutoff_at: cutoff,
        byte_limit: self.class::BATCH_UNCOMPRESSED_BYTE_LIMIT,
        partition_column: partition && self.class.partition_column,
        partition_value: partition&.value
      ).serialize

      begin
        archived_ids = serialized[:record_ids]
        return nil if archived_ids.empty?

        archive = upload_archive!(
          serialized: serialized,
          resource_type: self.class.archived_class.name,
          key: build_key(partition, archived_ids, self.class.resource_key_segment, self.class.key_prefix),
          cutoff: cutoff,
          partition: partition,
          record_ids: archived_ids
        )

        dependent_archives = archive_dependents!(archived_ids, cutoff, partition)

        culled = cull_archived_rows!(archive, dependent_archives, archived_ids, cutoff, partition, partition_predicate)

        { records: archived_ids.size, culled: culled }
      ensure
        File.unlink(serialized[:path]) if File.exist?(serialized[:path])
      end
    end

    # Uploads one serialized object and records it. Returns the Raif::Archive
    # row, which exists only because the object does.
    def upload_archive!(serialized:, resource_type:, key:, cutoff:, partition:, record_ids:)
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
      Raif::Archive.create!(
        resource_type: resource_type,
        key: key,
        location: location,
        cutoff_at: cutoff,
        partition_value: partition&.value,
        first_record_id: record_ids.first,
        last_record_id: record_ids.last,
        record_count: record_ids.size,
        compressed_bytes: serialized[:compressed_bytes],
        checksum_sha256: serialized[:checksum_sha256]
      )
    end

    # Final cull, atomic: re-select the serialized ids through the full
    # eligibility scope (and, when partitioning, the partition predicate)
    # with row locks, stamp, and delete in one transaction. The re-check
    # exists because the upload window can be long: a row mutated during it
    # must survive (its uploaded copy is stale) and re-enters a later batch
    # once quiescent again. The locks close the residual race between this
    # selection and the delete (e.g. a row terminalizing in that gap would
    # be deleted with an unstamped cost event). On failure, stamps and
    # deletes roll back together; the Archive rows stay outside the
    # transaction because they record the upload, not the cull, and the
    # uploaded objects remain the accepted harmless duplicate. The one
    # exception is a tainted partition (a record's partition value changed
    # during upload): the whole cull aborts and the objects and rows are
    # removed, because such an object misfiles a record under a prefix its
    # partition's purge could never find.
    def cull_archived_rows!(archive, dependent_archives, archived_ids, cutoff, partition, partition_predicate)
      self.class.archived_class.transaction do
        assert_partition_unchanged!(archived_ids, partition) if partition

        deletable_scope = self.class.eligible_scope(cutoff).where(id: archived_ids)
        deletable_scope = deletable_scope.where(partition_predicate) if partition_predicate
        deletable = deletable_scope.order(:id).lock.pluck(:id, :completed_at, :failed_at)
        deletable_ids = deletable.map(&:first)
        terminal_ids = deletable.filter_map { |id, completed_at, failed_at| id if completed_at || failed_at }

        # Stamp the archive link on the durable cost records BEFORE
        # deletion, so the stamp always means "culled into this archive".
        stamp_cost_events!(archive, terminal_ids)
        delete_dependents!(deletable_ids)

        self.class.archived_class.where(id: deletable_ids).in_batches(of: 5_000).delete_all
      end

      true
    rescue TaintedPartitionError
      ([archive] + dependent_archives).each { |tainted| cleanup_tainted_archive!(tainted) }
      false
    end

    # Locks every serialized row and verifies its partition value still
    # normalizes to this batch's partition. A record whose partition changed
    # during the upload window must not be culled: its uploaded copy sits
    # under the OLD partition's prefix, where the new partition's purge
    # could never find it. Locking here, before the eligibility recheck,
    # pins the values until commit.
    def assert_partition_unchanged!(archived_ids, partition)
      rows = self.class.archived_class.where(id: archived_ids).order(:id).lock.pluck(:id, self.class.partition_column)
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
        "#{self.class.name}: a record's #{self.class.partition_column} value changed during the " \
          "upload of #{archive.key}; aborted the cull and removing the tainted object. " \
          "Raif.config.archive_partition_column must be immutable for a record's lifetime."
      )

      storage = Raif.config.archive_storage
      unless storage.respond_to?(:delete)
        Rails.logger.error(
          "#{self.class.name}: cannot remove tainted object #{archive.key}: the archive_storage " \
            "adapter does not implement delete(key:); leaving the object and its Raif::Archive row in place"
        )
        return
      end

      storage.delete(key: archive.key)
      archive.destroy!
    rescue Raif::Errors::ArchiveStorageError => e
      Rails.logger.error(
        "#{self.class.name}: failed to remove tainted object #{archive.key} " \
          "(#{e.message}); leaving its Raif::Archive row in place"
      )
    end

    def build_key(partition, record_ids, segment, unpartitioned_prefix)
      prefix = partition ? "#{partition.storage_prefix}#{segment}" : unpartitioned_prefix

      # The 122 bits of run-suffix randomness make key reuse effectively
      # impossible: a re-run after a crash writes a fresh object instead of
      # resuming or overwriting (a collision would silently overwrite a
      # prior archive object whose rows were already deleted, before the DB
      # unique-key check could fire).
      "#{prefix}/#{record_ids.first}-#{record_ids.last}-#{Time.current.utc.strftime("%Y%m%dT%H%M%SZ")}-#{SecureRandom.uuid}.jsonl.gz"
    end

  end
end
