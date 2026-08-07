# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe Raif::Archive, type: :model do
  describe "validations" do
    it "requires the audit fields" do
      archive = described_class.new

      expect(archive).not_to be_valid
      expect(archive.errors.attribute_names).to include(
        :resource_type,
        :key,
        :location,
        :cutoff_at,
        :first_record_id,
        :last_record_id,
        :record_count,
        :compressed_bytes,
        :checksum_sha256
      )
    end

    it "enforces key uniqueness" do
      existing = FB.create(:raif_archive)
      duplicate = FB.build(:raif_archive, key: existing.key)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.attribute_names).to include(:key)
    end
  end

  describe ".covering" do
    let!(:archive_a) { FB.create(:raif_archive, first_record_id: 10, last_record_id: 20) }
    let!(:archive_b) { FB.create(:raif_archive, first_record_id: 30, last_record_id: 40) }
    let!(:other_resource_archive) { FB.create(:raif_archive, resource_type: "Document", first_record_id: 10, last_record_id: 40) }

    it "returns the archives whose id range contains the record" do
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 15)).to eq([archive_a])
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 30)).to eq([archive_b])
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 40)).to eq([archive_b])
    end

    it "returns all overlapping archives, newest first" do
      duplicate = FB.create(:raif_archive, first_record_id: 12, last_record_id: 25)

      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 15)).to eq([duplicate, archive_a])
    end

    it "is empty when no archive covers the record" do
      expect(described_class.covering(resource_type: "Raif::ModelCompletion", record_id: 25)).to be_empty
    end

    it "scopes by resource type" do
      expect(described_class.covering(resource_type: "Document", record_id: 25)).to eq([other_resource_archive])
    end
  end
end
