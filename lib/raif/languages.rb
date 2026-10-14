# frozen_string_literal: true

module Raif
  SUPPORTED_LANGUAGES = [
    "ar",
    "da",
    "de",
    "en",
    "es",
    "fi",
    "fr",
    "he",
    "hi",
    "it",
    "ja",
    "ko",
    "nl",
    "no",
    "pl",
    "pt",
    "ru",
    "sv",
    "th",
    "tr",
    "uk",
    "vi",
    "zh",
  ].freeze

  # A supported language with an optional region: "en", "en_gb", "en-GB", "es-419".
  LANGUAGE_KEY_FORMAT = /\A(?<language>[a-z]{2})(?:[-_](?<region>[a-z]{2}|\d{3}))?\z/i

  def self.supported_languages
    SUPPORTED_LANGUAGES
  end

  def self.supported_language_key?(key)
    language_key_parts(key).present?
  end

  # A region without its own `raif.languages` name reads as "English (AU)".
  def self.language_name(key)
    language, region = language_key_parts(key)
    return if language.nil?

    name = I18n.t("raif.languages.#{language}", locale: "en")
    return name if region.nil?

    I18n.t("raif.languages.#{language}_#{region.downcase}", locale: "en", default: "#{name} (#{region})")
  end

  def self.language_key_parts(key)
    match = LANGUAGE_KEY_FORMAT.match(key.to_s)
    return if match.nil? || !SUPPORTED_LANGUAGES.include?(match[:language].downcase)

    [match[:language].downcase, match[:region]&.upcase]
  end
  private_class_method :language_key_parts
end
