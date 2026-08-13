# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ArchiveStorage::FileSystem do
  let(:root) { Dir.mktmpdir }
  let(:adapter) { described_class.new(root: root) }
  let(:key) { "raif-archives/model-completions/1-100-20260101T000000Z-abc123.jsonl.gz" }
  let(:content) { "hello archive" }

  after { FileUtils.remove_entry(root) }

  describe "#write" do
    it "writes the io to the key path and returns a location" do
      location = adapter.write(key: key, io: StringIO.new(content), checksum_sha256: Digest::SHA256.hexdigest(content))

      expect(location).to eq(File.join(root, key))
      expect(File.read(location)).to eq(content)
    end

    it "raises on a checksum mismatch, the local equivalent of server-side upload verification" do
      expect do
        adapter.write(key: key, io: StringIO.new(content), checksum_sha256: Digest::SHA256.hexdigest("different content"))
      end.to raise_error(Raif::Errors::ArchiveStorageError, /checksum mismatch/)
    end

    it "rejects keys that escape the storage root" do
      expect do
        adapter.write(key: "../escape.txt", io: StringIO.new("nope"), checksum_sha256: "abc")
      end.to raise_error(ArgumentError, /escapes storage root/)
    end

    it "rejects sibling directories that share the root as a string prefix" do
      nested_adapter = described_class.new(root: File.join(root, "archive"))

      # Resolves to <root>/archive-evil/escape.txt, which passes a bare
      # prefix check against <root>/archive but is outside it.
      expect do
        nested_adapter.write(key: "../archive-evil/escape.txt", io: StringIO.new("nope"), checksum_sha256: "abc")
      end.to raise_error(ArgumentError, /escapes storage root/)
    end
  end

  describe "#delete" do
    def write_object(object_key, body = content)
      adapter.write(key: object_key, io: StringIO.new(body), checksum_sha256: Digest::SHA256.hexdigest(body))
    end

    it "deletes the object at the key" do
      location = write_object(key)

      adapter.delete(key: key)

      expect(File.exist?(location)).to be(false)
    end

    it "is idempotent: a missing object is a successful no-op" do
      expect { adapter.delete(key: key) }.not_to raise_error
    end

    it "rejects keys that escape the storage root" do
      expect { adapter.delete(key: "../escape.txt") }.to raise_error(ArgumentError, /escapes storage root/)
    end

    it "wraps filesystem failures in ArchiveStorageError" do
      location = write_object(key)
      allow(File).to receive(:unlink).and_call_original
      allow(File).to receive(:unlink).with(satisfy { |path| path.to_s.end_with?(key) }).and_raise(Errno::EACCES)

      expect { adapter.delete(key: key) }.to raise_error(Raif::Errors::ArchiveStorageError, /failed to delete/)

      # The stub stays active while the after hook removes the temp dir, so
      # remove the leftover object here via the unstubbed File.delete.
      File.delete(location)
    end
  end

  describe "#delete_prefix" do
    let(:prefix) { "raif-archives/partitions/#{Digest::SHA256.hexdigest("42")}/" }

    def write_object(object_key, body = content)
      adapter.write(key: object_key, io: StringIO.new(body), checksum_sha256: Digest::SHA256.hexdigest(body))
    end

    it "deletes every object under the prefix and returns the count" do
      write_object("#{prefix}model-completions/1-100-20260101T000000Z-abc.jsonl.gz")
      write_object("#{prefix}model-completions/101-200-20260102T000000Z-def.jsonl.gz")
      write_object("#{prefix}tasks/1-50-20260101T000000Z-ghi.jsonl.gz")
      survivor = write_object("raif-archives/partitions/#{Digest::SHA256.hexdigest("43")}/model-completions/1-9-x.jsonl.gz")

      expect(adapter.delete_prefix(prefix: prefix)).to eq(3)

      expect(Dir.exist?(File.join(root, prefix))).to be(false)
      expect(File.exist?(survivor)).to be(true)
    end

    it "is idempotent: a missing prefix is a successful no-op returning 0" do
      expect(adapter.delete_prefix(prefix: prefix)).to eq(0)
    end

    it "rejects prefixes that escape the storage root" do
      expect { adapter.delete_prefix(prefix: "../") }.to raise_error(ArgumentError, /escapes storage root/)
    end

    it "rejects a blank prefix rather than deleting the whole root" do
      survivor = write_object("raif-archives/model-completions/1-2-x.jsonl.gz")

      expect { adapter.delete_prefix(prefix: "") }.to raise_error(ArgumentError, /escapes storage root/)

      expect(File.exist?(survivor)).to be(true)
    end

    it "rejects sibling directories that share the root as a string prefix" do
      nested_adapter = described_class.new(root: File.join(root, "archive"))

      expect do
        nested_adapter.delete_prefix(prefix: "../archive-evil/")
      end.to raise_error(ArgumentError, /escapes storage root/)
    end

    it "wraps filesystem failures in ArchiveStorageError" do
      write_object("#{prefix}model-completions/1-100-20260101T000000Z-abc.jsonl.gz")
      # Scoped to the prefix directory so the temp-dir cleanup in the after
      # hook is unaffected.
      allow(FileUtils).to receive(:remove_entry).and_call_original
      allow(FileUtils).to receive(:remove_entry)
        .with(satisfy { |path| path.to_s.include?("raif-archives/partitions") })
        .and_raise(Errno::EACCES)

      expect { adapter.delete_prefix(prefix: prefix) }.to raise_error(Raif::Errors::ArchiveStorageError, /failed to delete prefix/)
    end
  end
end
