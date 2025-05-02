# frozen_string_literal: true

class Raif::ModelFileInput
  include ActiveModel::Model

  attr_accessor :input, :url, :base64_data, :filename, :content_type, :source_type

  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "is not a valid URL" }, allow_nil: true
  validates :base64_data, presence: { message: "could not be read from input" }, if: -> { input.present? }
  validates :content_type, presence: { message: "could not be determined" }, if: -> { input.present? }

  def initialize(input: nil, url: nil)
    raise ArgumentError, "You must provide either an input or a URL" if input.blank? && url.blank?
    raise ArgumentError, "Provide either input or URL, not both" if input.present? && url.present?

    super(input: input, url: url)

    if url.present?
      @source_type = :url
    elsif input.present?
      @source_type = :file_content
      process_input!
    end

    unless valid?
      raise Raif::Errors::InvalidModelFileInputError, errors.full_messages.join(", ")
    end
  end

  def inspect
    "#<#{self.class.name} input=#{input.inspect} url=#{url.inspect} base64_data=#{base64_data&.truncate(20)} filename=#{filename.inspect} content_type=#{content_type.inspect} source_type=#{source_type.inspect}>" # rubocop:disable Layout/LineLength
  end

  def file_bytes
    Base64.strict_decode64(base64_data)
  end

private

  def process_input!
    if input_is_active_storage_blob?
      process_active_storage_blob(input)
      return
    elsif input_has_active_storage_blob?
      process_active_storage_blob(input.blob)
      return
    end

    case input
    when String
      process_string_input
    when Pathname
      process_from_path
    when File, Tempfile, IO, StringIO
      read_from_io
    else
      raise Raif::Errors::InvalidModelFileInputError, "Invalid input type for #{self.class.name} (got #{input.class})"
    end
  end

  def process_string_input
    if File.exist?(input)
      @input = Pathname.new(input)
      process_from_path
    else
      raise Raif::Errors::InvalidModelFileInputError, "File does not exist: #{input}"
    end
  end

  def process_active_storage_blob(blob)
    @filename = blob.filename.to_s
    @content_type = blob.content_type
    @base64_data = Base64.strict_encode64(blob.download)
  end

  def process_from_path
    @filename = input.basename.to_s
    @content_type = Marcel::MimeType.for(input)
    @base64_data = Base64.strict_encode64(input.binread)
  end

  def read_from_io
    @filename = input.respond_to?(:path) ? File.basename(input.path) : nil
    @content_type = Marcel::MimeType.for(input)
    try_rewind
    @base64_data = Base64.strict_encode64(input.read)
  end

  def try_rewind
    input.rewind if input.respond_to?(:rewind)
  rescue IOError => e
    logger.error "Failed to rewind IO: #{e.message}"
    logger.error e.backtrace.join("\n")
  end

  def input_looks_like_base64?
    input.match?(%r{\A[a-zA-Z0-9+/\n\r]+={0,2}\z})
  end

  def input_has_active_storage_blob?
    return false unless defined?(ActiveStorage)
    return false unless input.respond_to?(:blob)

    input.blob.is_a?(ActiveStorage::Blob)
  end

  def input_is_active_storage_blob?
    return false unless defined?(ActiveStorage)

    input.is_a?(ActiveStorage::Blob)
  end

end
