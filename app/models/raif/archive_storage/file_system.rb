# frozen_string_literal: true

module Raif
  module ArchiveStorage
    # Local-disk reference implementation of the archive storage adapter
    # contract (Raif.config.archive_storage): write returns a location
    # string and raises on any failure; delete and delete_prefix are
    # idempotent (a missing object or prefix succeeds) and wrap any
    # filesystem failure in Raif::Errors::ArchiveStorageError. Only write is
    # required of every adapter; delete supports cleanup of an invalid
    # just-uploaded object and delete_prefix supports
    # Raif::Archive.purge_partition!, so hosts implement them only when they
    # use the corresponding feature. Used by Raif's own test suite and
    # suitable for small hosts; production hosts typically supply their own
    # adapter (e.g. S3-backed, passing checksum_sha256 on the PUT so the
    # store verifies integrity server-side).
    class FileSystem
      attr_reader :root

      def initialize(root:)
        @root = Pathname.new(root)
      end

      # Verifies the written bytes against checksum_sha256 before returning,
      # the local-disk equivalent of a remote store's server-side upload
      # integrity verification (e.g. S3 checking checksum_sha256 on the PUT).
      def write(key:, io:, checksum_sha256:)
        path = path_for(key)
        path.dirname.mkpath
        IO.copy_stream(io, path)

        written_checksum = Digest::SHA256.file(path).hexdigest
        if written_checksum != checksum_sha256
          raise Raif::Errors::ArchiveStorageError,
            "checksum mismatch after writing #{key}: expected #{checksum_sha256}, wrote #{written_checksum}"
        end

        path.to_s
      end

      # Idempotent single-object deletion: a missing object is a successful
      # no-op. Used for best-effort cleanup of a just-uploaded object whose
      # cull was aborted (see Raif::ArchiveModelCompletionsJob).
      def delete(key:)
        path = path_for(key)
        begin
          File.unlink(path)
        rescue Errno::ENOENT
          # Already gone: deletion is idempotent.
        rescue SystemCallError => e
          raise Raif::Errors::ArchiveStorageError, "failed to delete #{key}: #{e.class}: #{e.message}"
        end

        true
      end

      # Idempotent prefix deletion returning the number of objects removed;
      # a missing prefix is a successful no-op returning 0. Used by
      # Raif::Archive.purge_partition! for complete erasure of a partition,
      # crash-orphaned uploads included.
      def delete_prefix(prefix:)
        dir = contained_path(prefix, kind: "prefix")
        return 0 unless dir.exist?

        begin
          object_count = dir.glob("**/*", File::FNM_DOTMATCH).count(&:file?)
          FileUtils.remove_entry(dir)
          object_count
        rescue SystemCallError => e
          raise Raif::Errors::ArchiveStorageError, "failed to delete prefix #{prefix}: #{e.class}: #{e.message}"
        end
      end

    private

      def path_for(key)
        contained_path(key, kind: "key")
      end

      def contained_path(relative, kind:)
        path = root.join(relative)
        # Keys and prefixes are generated internally, but a hostile or buggy
        # value must not escape the adapter's root. The trailing separator
        # makes the check path-component-aware: without it, a sibling like
        # /tmp/archive-evil passes a bare prefix check against /tmp/archive.
        # A blank value cleans to the root itself and is rejected too (a
        # blank prefix must never delete the whole root).
        unless path.cleanpath.to_s.start_with?(root.cleanpath.to_s + File::SEPARATOR)
          raise ArgumentError, "#{kind} escapes storage root: #{relative}"
        end

        path
      end
    end
  end
end
