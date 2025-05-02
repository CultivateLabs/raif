# frozen_string_literal: true

require "rails_helper"

RSpec.describe Raif::ModelImageInput, type: :model do
  let(:file_path) { Raif::Engine.root.join("spec/fixtures/files/cultivate.png") }
  let(:base64_string) { Base64.strict_encode64(File.binread(file_path)) }

  it "requires either an input or a URL" do
    expect { described_class.new }.to raise_error(ArgumentError, "You must provide either an input or a URL")
  end

  it "doesn't allow both input and URL" do
    expect do
      described_class.new(input: file_path, url: "https://example.com/cultivate.png")
    end.to raise_error(ArgumentError, "Provide either input or URL, not both")
  end

  it "raises an error for an unsupported object" do
    expect { described_class.new(input: Object.new) }.to raise_error(Raif::Errors::InvalidModelFileInputError)
  end

  it "raises an error for an invalid URL" do
    expect do
      described_class.new(url: "invalid-url")
    end.to raise_error(Raif::Errors::InvalidModelFileInputError, "Url is not a valid URL")
  end

  it "raises an error when the file is missing" do
    expect do
      described_class.new(input: "missing.png")
    end.to raise_error(Raif::Errors::InvalidModelFileInputError, "File does not exist: missing.png")
  end

  it "raises an error when unable to populate base64 data" do
    allow(Base64).to receive(:strict_encode64).and_return(nil)
    expect do
      described_class.new(input: file_path)
    end.to raise_error(Raif::Errors::InvalidModelFileInputError, "Base64 data could not be read from input")
  end

  it "raises an error when content type cannot be determined" do
    allow(Marcel::MimeType).to receive(:for).and_return(nil)
    expect do
      described_class.new(input: file_path)
    end.to raise_error(Raif::Errors::InvalidModelFileInputError, "Content type could not be determined")
  end

  it "handles URL input" do
    input = described_class.new(url: "https://example.com/cultivate.png")
    expect(input).to be_valid
    expect(input.source_type).to eq(:url)
    expect(input.base64_data).to be_nil
    expect(input.filename).to be_nil
    expect(input.content_type).to be_nil
  end

  it "handles a file path input" do
    input = described_class.new(input: file_path)
    expect(input).to be_valid
    expect(input.source_type).to eq(:file_content)
    expect(input.base64_data).to eq(base64_string)
    expect(input.filename).to eq("cultivate.png")
    expect(input.content_type).to eq("image/png")
  end

  it "handles a file path input" do
    input = described_class.new(input: file_path)
    expect(input).to be_valid
    expect(input.source_type).to eq(:file_content)
    expect(input.base64_data).to eq(base64_string)
    expect(input.filename).to eq("cultivate.png")
    expect(input.content_type).to eq("image/png")
  end

  it "handles a File object input" do
    input = described_class.new(input: File.open(file_path))
    expect(input).to be_valid
    expect(input.source_type).to eq(:file_content)
    expect(input.base64_data).to eq(base64_string)
    expect(input.filename).to eq("cultivate.png")
    expect(input.content_type).to eq("image/png")
  end

  it "handles a StringIO object input" do
    input = described_class.new(input: StringIO.new(File.binread(file_path)))
    expect(input).to be_valid
    expect(input.source_type).to eq(:file_content)
    expect(input.base64_data).to eq(base64_string)
    expect(input.filename).to eq(nil)
    expect(input.content_type).to eq("image/png")
  end

  it "handles an ActiveStorage::Attached object" do
    user = FactoryBot.create(:raif_test_user)
    user.documents.attach(io: File.open(file_path), filename: "cultivate.png", content_type: "image/png")
    input = described_class.new(input: user.documents.first)
    expect(input).to be_valid
    expect(input.source_type).to eq(:file_content)
    expect(input.base64_data).to eq(base64_string)
    expect(input.filename).to eq("cultivate.png")
    expect(input.content_type).to eq("image/png")
  end

  it "handles an ActiveStorage::Blob object" do
    user = FactoryBot.create(:raif_test_user)
    user.documents.attach(io: File.open(file_path), filename: "cultivate.png", content_type: "image/png")
    input = described_class.new(input: user.documents.first.blob)
    expect(input).to be_valid
    expect(input.source_type).to eq(:file_content)
    expect(input.base64_data).to eq(base64_string)
    expect(input.filename).to eq("cultivate.png")
    expect(input.content_type).to eq("image/png")
  end
end
