# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ArchiveSerializer do
  let(:cutoff_at) { 6.months.ago }
  let(:byte_limit) { 512.megabytes }

  let!(:completions) do
    3.times.map do |i|
      FB.create(
        :raif_model_completion,
        llm_model_key: "raif_test_llm",
        model_api_name: "raif-test-llm",
        citations: [{ "url" => "https://example.com/#{i}", "title" => "Source #{i}" }],
        messages: [{ "role" => "user", "content" => "Message #{i}" }]
      )
    end
  end

  def serialize(relation = Raif::ModelCompletion.where(id: completions.map(&:id)), limit: byte_limit)
    result = described_class.new(relation: relation, cutoff_at: cutoff_at, byte_limit: limit).serialize
    @result_path = result[:path]
    result
  end

  def read_lines(path)
    Zlib::GzipReader.open(path) { |gz| gz.read.split("\n") }
  end

  after { File.unlink(@result_path) if @result_path && File.exist?(@result_path) }

  it "writes a versioned manifest as line 1" do
    result = serialize
    manifest = JSON.parse(read_lines(result[:path]).first)

    expect(manifest["manifest_version"]).to eq(1)
    expect(manifest["resource_type"]).to eq("Raif::ModelCompletion")
    expect(manifest["table"]).to eq("raif_model_completions")
    expect(manifest["columns"]).to eq(Raif::ModelCompletion.column_names)
    expect(Time.zone.parse(manifest["cutoff_at"])).to be_within(1.second).of(cutoff_at)
    expect(manifest["first_record_id"]).to eq(completions.map(&:id).min)
    expect(manifest["last_record_id"]).to eq(completions.map(&:id).max)
    expect(manifest["record_count"]).to eq(3)
    expect(manifest["generated_at"]).to be_present
  end

  it "round-trips every attribute, including jsonb columns" do
    result = serialize
    lines = read_lines(result[:path])
    records = lines.drop(1).map { |line| JSON.parse(line) }

    expect(records.size).to eq(3)

    completions.each_with_index do |completion, i|
      record = records.find { |r| r["id"] == completion.id }
      expect(record).to be_present
      expect(record.keys).to match_array(Raif::ModelCompletion.column_names)
      expect(record["citations"]).to eq([{ "url" => "https://example.com/#{i}", "title" => "Source #{i}" }])
      expect(record["messages"]).to eq([{ "role" => "user", "content" => "Message #{i}" }])
      expect(record["llm_model_key"]).to eq("raif_test_llm")
      expect(Time.zone.parse(record["created_at"])).to be_within(0.001.seconds).of(completion.created_at)
    end
  end

  it "returns the checksum, compressed size, and the ids actually written" do
    result = serialize

    expect(result[:checksum_sha256]).to eq(Digest::SHA256.file(result[:path]).hexdigest)
    expect(result[:compressed_bytes]).to eq(File.size(result[:path]))
    expect(result[:record_ids]).to eq(completions.map(&:id).sort)
  end

  it "serializes exactly the given ids, in primary key order" do
    subset = completions.map(&:id).sort.first(2)
    result = serialize(Raif::ModelCompletion.where(id: subset))
    ids = read_lines(result[:path]).drop(1).map { |line| JSON.parse(line)["id"] }

    expect(ids).to eq(subset)
    expect(result[:record_ids]).to eq(subset)
  end

  describe "byte cap" do
    it "closes the batch early when the uncompressed byte limit is reached, and the manifest counts only what was written" do
      result = serialize(limit: 1)

      expect(result[:record_ids]).to eq([completions.map(&:id).min])

      lines = read_lines(result[:path])
      manifest = JSON.parse(lines.first)
      expect(manifest["record_count"]).to eq(1)
      expect(manifest["first_record_id"]).to eq(completions.map(&:id).min)
      expect(manifest["last_record_id"]).to eq(completions.map(&:id).min)
      expect(lines.size).to eq(2)
    end

    it "always includes at least one record, even when a single record exceeds the limit" do
      result = serialize(Raif::ModelCompletion.where(id: completions.first.id), limit: 1)

      expect(result[:record_ids]).to eq([completions.first.id])
    end
  end
end
