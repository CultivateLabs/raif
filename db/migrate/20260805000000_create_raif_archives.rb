# frozen_string_literal: true

class CreateRaifArchives < ActiveRecord::Migration[7.1]
  def change
    create_table :raif_archives do |t|
      # The archived resource class (e.g. "Raif::ModelCompletion"). Kept
      # generic: any archivable resource shares this table.
      t.string :resource_type, null: false
      # Storage key. Never reused across runs: a re-run after a crash writes
      # a new object under a new key rather than resuming or overwriting.
      t.string :key, null: false
      # Adapter-returned locator (may equal key).
      t.string :location
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

      t.timestamps
    end

    add_index :raif_archives,
      [:resource_type, :first_record_id, :last_record_id],
      name: "index_raif_archives_on_resource_type_and_record_id_range"
    add_index :raif_archives, :key, unique: true

    # Stamped at cull time, immediately before the archived completions are
    # deleted, so culled spend links directly to the archive that holds its
    # completion. ON DELETE SET NULL: the durable cost record must never
    # dangle or block, even if an archive row is pruned.
    add_reference :raif_inference_cost_events,
      :raif_archive,
      null: true,
      foreign_key: { to_table: :raif_archives, on_delete: :nullify }
  end
end
