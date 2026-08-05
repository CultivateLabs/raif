# frozen_string_literal: true

# Serializes an ordered relation of records to a gzip-compressed JSON Lines
# tempfile for archival:
#
# - Line 1 is a versioned manifest: resource type, table, columns, cutoff,
#   the serialized id range/count, and generation time.
# - Lines 2..n are one record per line: the full record.attributes as JSON,
#   complete raw attributes including ids and polymorphic references, NOT a
#   reduced projection. Round-trippable for manual recovery or re-insertion
#   with original ids.
#
# Serialization stops early when the running uncompressed byte total reaches
# byte_limit (completion payloads vary wildly; a pure record count could
# otherwise build a multi-GB file). At least one record is always written so
# an oversized single record still archives. The manifest must be line 1 but
# its record count/range aren't known until the byte cap resolves, so records
# spool uncompressed to a scratch tempfile first, then manifest + records are
# gzip-written to the final file. record_ids in the result is the ids
# ACTUALLY written - the caller must upload, record, and delete exactly that
# subset; anything cut off by the cap simply stays eligible for a later
# batch.
#
# Resource-agnostic by design: nothing here may know about
# Raif::ModelCompletion specifics, because Raif::Task archiving (and any host
# resource) reuses this class.
class Raif::ArchiveSerializer
  MANIFEST_VERSION = 1

  # relation: the exact records to serialize (callers pass a frozen id set,
  # never a bare range), streamed in primary key order via find_each.
  def initialize(relation:, cutoff_at:, byte_limit:, tmp_dir: Rails.root.join("tmp"))
    @relation = relation
    @cutoff_at = cutoff_at
    @byte_limit = byte_limit
    @tmp_dir = tmp_dir.to_s
  end

  # => { path:, checksum_sha256:, compressed_bytes:, record_ids: }
  # The caller owns the file at path: and must delete it when done.
  def serialize
    record_ids = []

    Tempfile.create(["raif-archive-spool", ".jsonl"], @tmp_dir) do |spool|
      spool.binmode
      uncompressed_bytes = 0

      @relation.find_each do |record|
        # to_json (not JSON.generate) so ActiveSupport encodes timestamps as
        # ISO8601 with sub-second precision; round-trip fidelity matters.
        line = "#{record.attributes.to_json}\n"
        spool.write(line)
        record_ids << record.id
        uncompressed_bytes += line.bytesize
        break if uncompressed_bytes >= @byte_limit
      end

      spool.flush
      spool.rewind

      path = write_gzip_file(spool, record_ids)

      {
        path: path,
        checksum_sha256: Digest::SHA256.file(path).hexdigest,
        compressed_bytes: File.size(path),
        record_ids: record_ids
      }
    end
  end

private

  def write_gzip_file(spool, record_ids)
    # Tempfile.create without a block: the file is NOT auto-deleted, which is
    # what we want since the caller uploads and then deletes it.
    file = Tempfile.create(["raif-archive", ".jsonl.gz"], @tmp_dir)

    begin
      file.binmode
      gz = Zlib::GzipWriter.new(file)
      gz.write("#{manifest(record_ids).to_json}\n")

      while (chunk = spool.read(1.megabyte))
        gz.write(chunk)
      end

      gz.close # closes the underlying file too
      file.path
    rescue StandardError
      File.unlink(file.path) if File.exist?(file.path)
      raise
    end
  end

  def manifest(record_ids)
    {
      manifest_version: MANIFEST_VERSION,
      resource_type: @relation.klass.base_class.name,
      table: @relation.klass.table_name,
      columns: @relation.klass.column_names,
      cutoff_at: @cutoff_at,
      first_record_id: record_ids.first,
      last_record_id: record_ids.last,
      record_count: record_ids.size,
      generated_at: Time.current
    }
  end
end
