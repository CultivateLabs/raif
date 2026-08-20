# frozen_string_literal: true

# Transactional schema additions only. The concurrent index on the (large,
# hot in host apps) raif_inference_cost_events table lives in the next
# migration: a concurrent index build requires disabling the DDL transaction,
# and a non-transactional migration that fails partway is not retryable (the
# already-created table blocks the re-run while schema_migrations has no
# record of the version).
class CreateRaifArchives < ActiveRecord::Migration[7.1]
  def change
    create_table :raif_archives do |t|
      # The archived resource class (e.g. "Raif::ModelCompletion"). Kept
      # generic: any archivable resource shares this table.
      t.string :resource_type, null: false
      # Storage key. Never reused across runs: a re-run after a crash writes
      # a new object under a new key rather than resuming or overwriting.
      t.string :key, null: false
      # Adapter-returned locator (may equal key). Required: a blank locator
      # means the storage adapter did not follow the write contract, and the
      # job refuses to record (or delete against) such an upload.
      t.string :location, null: false
      # Retention cutoff frozen at job start for this batch.
      t.datetime :cutoff_at, null: false
      # Inclusive id range of the archived records: the permanent, compact
      # index used by Raif::Archive.covering to find the archives holding a
      # given culled record.
      t.bigint :first_record_id, null: false
      t.bigint :last_record_id, null: false
      t.integer :record_count, null: false
      t.bigint :compressed_bytes, null: false
      t.string :checksum_sha256, null: false
      # Normalized partition value (see Raif.config.archive_partition_column)
      # for the records in this object. NULL when partitioning is unset or
      # the object holds explicitly ungrouped records.
      t.string :partition_value

      t.timestamps
    end

    add_index :raif_archives,
      [:resource_type, :first_record_id, :last_record_id],
      name: "index_raif_archives_on_resource_type_and_record_id_range"
    add_index :raif_archives, :key, unique: true
    # On partition_value alone: a partition purge spans resource types.
    add_index :raif_archives, :partition_value

    # Stamped at cull time, immediately before the archived completions are
    # deleted, so culled spend links directly to the archive that holds its
    # completion. Plain bigint, no FK: adding a foreign key to a host's
    # large, hot events table blocks writes on both tables while it
    # validates (strong_migrations-style host policies reject that
    # outright), and no dangling stamp can arise without one: purge
    # nullifies stamps transactionally before deleting archive rows, and
    # tainted-upload cleanup only deletes an archive row whose cull (and
    # therefore stamps) already rolled back. Consistent with the other
    # linkage columns on this table (source_id,
    # original_model_completion_id).
    add_column :raif_inference_cost_events, :raif_archive_id, :bigint
  end
end
