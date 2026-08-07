# frozen_string_literal: true

module Raif
  module ArchiveStorage
    # Local-disk reference implementation of the archive storage adapter
    # contract (Raif.config.archive_storage): a single write method that
    # returns a location string and raises on any failure. Used by Raif's own
    # test suite and suitable for small hosts; production hosts typically
    # supply their own adapter (e.g. S3-backed, passing checksum_sha256 on
    # the PUT so the store verifies integrity server-side).
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

    private

      def path_for(key)
        path = root.join(key)
        # Keys are generated internally, but a hostile or buggy key must not
        # escape the adapter's root. The trailing separator makes the check
        # path-component-aware: without it, a sibling like
        # /tmp/archive-evil passes a bare prefix check against /tmp/archive.
        raise ArgumentError, "key escapes storage root: #{key}" unless path.cleanpath.to_s.start_with?(root.cleanpath.to_s + File::SEPARATOR)

        path
      end
    end
  end
end
