# frozen_string_literal: true

FactoryBot.define do
  factory :raif_archive, class: "Raif::Archive" do
    resource_type { "Raif::ModelCompletion" }
    cutoff_at { 6.months.ago }
    first_record_id { 1 }
    last_record_id { 100 }
    record_count { 100 }
    compressed_bytes { 1024 }
    checksum_sha256 { Digest::SHA256.hexdigest("test") }
    sequence(:key) { |i| "raif-archives/model-completions/#{i}-#{i + 99}-20260101T000000Z-abc#{i}.jsonl.gz" }
    location { key }
  end
end
