# frozen_string_literal: true

class Raif::ApplicationRecord < Raif.config.model_superclass.constantize
  include Raif::Concerns::BooleanTimestamp

  self.abstract_class = true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }

  # Returns a scope that checks if a JSON column is not blank (not null and not empty array)
  # @param column_name [Symbol, String] the name of the JSON column
  # @return [ActiveRecord::Relation]
  def self.where_json_not_blank(column_name)
    quoted_column = connection.quote_column_name(column_name.to_s)

    case connection.adapter_name.downcase
    when "postgresql"
      where.not(column_name => nil)
        .where("jsonb_array_length(#{quoted_column}) > 0")
    when "mysql2", "trilogy"
      where.not(column_name => nil)
        .where("JSON_LENGTH(#{quoted_column}) > 0")
    else
      raise "Unsupported database: #{connection.adapter_name}"
    end
  end

  def self.table_name_prefix
    "raif_"
  end
end
