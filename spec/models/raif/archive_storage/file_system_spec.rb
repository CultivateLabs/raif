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
end
