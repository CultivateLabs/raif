# frozen_string_literal: true

# Value object for one archive partition (see
# Raif.config.archive_partition_column): the single owner of partition value
# normalization, the storage token, and the storage key prefix. Partition
# batching, archive key building, and Raif::Archive.purge_partition! all
# derive these through this class, so integer vs. string inputs of the same
# host value can never produce diverging stored values, tokens, or purge
# targets.
#
# Normalization is exactly value.to_s (no stripping); values that normalize
# to blank are rejected (fail closed). The storage token is the SHA-256 hex
# digest of the normalized value: path-safe for arbitrary host values and
# free of host identifiers in storage paths. The raw normalized value lives
# on Raif::Archive#partition_value, and the token is re-derivable from any
# candidate value.
#
# The partition prefix sits ABOVE the resource type in the key layout
# (raif-archives/partitions/<token>/<resource-type>/...), so deleting one
# partition prefix erases every archived resource type for that partition,
# including crash-orphaned uploads, without enumerating resource types.
class Raif::ArchivePartition
  PREFIX_ROOT = "raif-archives/partitions"
  # Reserved segment for explicitly ungrouped records
  # (Raif.config.archive_partition_fallback = Raif::Archive::UNGROUPED).
  # Cannot collide with a real value: real values always hash to a hex
  # token, so a host value normalizing to the string "_ungrouped" never
  # lands in this segment.
  UNGROUPED_SEGMENT = "_ungrouped"

  # value.to_s normalized string for a real partition; nil for the reserved
  # ungrouped partition (stored as NULL on Raif::Archive#partition_value).
  attr_reader :value

  def self.for(value)
    return ungrouped if value.equal?(Raif::Archive::UNGROUPED)

    normalized = value.to_s
    if normalized.blank?
      raise ArgumentError,
        "partition value must not normalize to blank (got #{value.inspect}); " \
          "records without partition attribution fail closed and are never archived"
    end

    new(value: normalized)
  end

  def self.ungrouped
    new(value: nil)
  end

  private_class_method :new

  def initialize(value:)
    @value = value
  end

  def ungrouped?
    value.nil?
  end

  # Path segment identifying this partition in storage: a SHA-256 hex token
  # for real values, the reserved literal segment for ungrouped.
  def token
    ungrouped? ? UNGROUPED_SEGMENT : Digest::SHA256.hexdigest(value)
  end

  # Storage prefix (trailing slash included) under which every archive
  # object for this partition lives. purge_partition! deletes exactly this
  # prefix; key building appends <resource-type>/<object-name> to it.
  def storage_prefix
    "#{PREFIX_ROOT}/#{token}/"
  end
end
