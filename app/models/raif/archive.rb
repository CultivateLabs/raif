# frozen_string_literal: true

# Append-only log of uploaded archive objects: one row per gzip JSONL file
# written by an archive job (see Raif::ArchiveModelCompletionsJob). A row is
# created only after its object was successfully uploaded, in the same run
# that then deletes the archived rows - row exists = object uploaded, and
# that is the entire lifecycle. No readback or restore ships in v1; the row
# identifies the object and retrieval is a manual operation.
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
#  index_raif_archives_on_resource_type_and_record_id_range  (resource_type,first_record_id,last_record_id)
#
class Raif::Archive < Raif::ApplicationRecord
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
end
