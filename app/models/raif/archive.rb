# frozen_string_literal: true

# Log of uploaded archive objects: one row per gzip JSONL file written by an
# archive job (see Raif::ArchiveModelCompletionsJob). A row is created only
# after its object was successfully uploaded, in the same run that then
# deletes the archived rows - row exists = object uploaded. Rows are deleted
# in exactly two cases, each together with its object: the archive job's
# cleanup of a tainted upload (a record's partition value changed mid-run),
# and .purge_partition! completely erasing one partition's archives. No
# readback or restore ships in v1; the row identifies the object and
# retrieval is a manual operation.
# == Schema Information
#
# Table name: raif_archives
#
#  id               :bigint           not null, primary key
#  checksum_sha256  :string           not null
#  compressed_bytes :bigint           not null
#  cutoff_at        :datetime         not null
#  key              :string           not null
#  location         :string           not null
#  partition_value  :string
#  record_count     :integer          not null
#  resource_type    :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  first_record_id  :bigint           not null
#  last_record_id   :bigint           not null
#
# Indexes
#
#  index_raif_archives_on_key                                (key) UNIQUE
#  index_raif_archives_on_partition_value                    (partition_value)
#  index_raif_archives_on_resource_type_and_record_id_range  (resource_type,first_record_id,last_record_id)
#
class Raif::Archive < Raif::ApplicationRecord
  # Convenience alias for the ungrouped-fallback sentinel. The canonical
  # constant lives on Raif::ArchivePartition (an eagerly required lib file)
  # because host initializers must be able to reference it before the
  # engine's app/ autoload paths exist; in an initializer, use
  # Raif::ArchivePartition::UNGROUPED.
  UNGROUPED = Raif::ArchivePartition::UNGROUPED

  has_many :raif_inference_cost_events,
    class_name: "Raif::InferenceCostEvent",
    foreign_key: :raif_archive_id,
    inverse_of: :raif_archive,
    dependent: nil

  validates :resource_type, presence: true
  validates :key, presence: true, uniqueness: true
  validates :location, presence: true
  validates :cutoff_at, presence: true
  validates :first_record_id, presence: true
  validates :last_record_id, presence: true
  validates :record_count, presence: true
  validates :compressed_bytes, presence: true
  validates :checksum_sha256, presence: true

  # Operator forensic helper: the archive rows whose id range contains the
  # record, i.e. the CANDIDATE objects to search when manually recovering a
  # culled record. A range match does not prove membership - eligibility
  # guards can exclude ids inside an archived range, and a record deleted
  # outside the archive job was never archived at all - so application code
  # (e.g. the admin "archived" badge) must rely on the
  # raif_inference_cost_events.raif_archive_id stamp instead. Ranges from
  # different runs can overlap when a crash between upload and delete
  # produced a duplicate object, so this returns all matches, newest first.
  def self.covering(resource_type:, record_id:)
    where(resource_type: resource_type)
      .where("first_record_id <= :record_id AND last_record_id >= :record_id", record_id: record_id)
      .order(id: :desc)
  end

  def resource_class
    resource_type.constantize
  end

  # Complete erasure of one partition's archives (see
  # Raif.config.archive_partition_column): deletes the partition's entire
  # storage prefix, spanning every archived resource type and including
  # crash-orphaned uploads that have no Raif::Archive row, then
  # transactionally nullifies surviving cost event stamps and deletes the
  # partition's Raif::Archive rows.
  #
  # Deliberately independent of the archival feature flags: erasure
  # obligations outlive them, so this works with archive_enabled false and
  # with archive_partition_column since unset. Only a configured
  # archive_storage adapter implementing delete_prefix(prefix:) is required
  # (validated here, at invocation).
  #
  # Retry-safe in both directions: a storage failure aborts before any DB
  # change, and a DB failure after prefix deletion re-runs cleanly because
  # prefix deletion is idempotent. Runs under the same advisory lock as
  # Raif::ArchiveModelCompletionsJob (a concurrent run must not write new
  # objects into the prefix mid-purge) and raises the retryable
  # Raif::Errors::ArchiveBusyError when the lock is held.
  #
  # Returns a structured summary and emits it via
  # ActiveSupport::Notifications ("purge_partition.raif"). Raif persists no
  # compliance audit record of its own (that would create a new retained
  # identifier inside an erasure workflow); the host decides whether to
  # persist a suitably de-identified audit from the returned summary.
  def self.purge_partition!(partition_value:)
    if partition_value.equal?(UNGROUPED)
      raise ArgumentError,
        "Raif::Archive.purge_partition! cannot purge the reserved ungrouped partition; " \
          "it holds records the host explicitly declared unowned"
    end

    partition = Raif::ArchivePartition.for(partition_value)

    storage = Raif.config.archive_storage
    unless storage.respond_to?(:delete_prefix)
      raise Raif::Errors::InvalidConfigError,
        "Raif::Archive.purge_partition! requires Raif.config.archive_storage to implement " \
          "delete_prefix(prefix:) (got #{storage.inspect})"
    end

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = nil

    ran = Raif::ArchiveAdvisoryLock.acquire do
      # Storage first: if this raises, the DB audit state is still intact
      # for a retry. The prefix covers tracked and crash-orphaned objects
      # alike, with no enumeration of resource types.
      objects_deleted = storage.delete_prefix(prefix: partition.storage_prefix)

      archive_rows_deleted = nil
      stamps_nullified = nil
      transaction do
        # Ungrouped and unpartitioned archives store partition_value as
        # NULL, so this non-blank match can never touch them. SQL equality
        # can also be LOOSER than the normalized value (MySQL's
        # case-insensitive collations match case variants), and an
        # over-matched row belongs to a different partition whose objects
        # live under a different prefix; deleting it would orphan them. So
        # only rows whose stored value matches exactly are purged, the same
        # re-check the archive job applies at selection. The advisory lock
        # keeps the id list stable: nothing else inserts archive rows.
        purged_ids = where(partition_value: partition.value)
          .pluck(:id, :partition_value)
          .select { |_id, value| value == partition.value }
          .map(&:first)

        stamps_nullified = Raif::InferenceCostEvent
          .where(raif_archive_id: purged_ids)
          .update_all(raif_archive_id: nil)
        archive_rows_deleted = where(id: purged_ids).delete_all
      end

      result = {
        partition_value: partition.value,
        prefix: partition.storage_prefix,
        objects_deleted: objects_deleted,
        archive_rows_deleted: archive_rows_deleted,
        stamps_nullified: stamps_nullified,
        duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      }
    end

    unless ran
      raise Raif::Errors::ArchiveBusyError,
        "Raif::Archive.purge_partition! could not acquire the archive advisory lock (an archive job run or " \
          "another purge is in progress); nothing was deleted, retry later"
    end

    ActiveSupport::Notifications.instrument("purge_partition.raif", result)
    result
  end
end
