# frozen_string_literal: true

FactoryBot.define do
  factory :raif_test_user, class: "Raif::TestUser" do
    sequence(:email){|i| "user-#{SecureRandom.hex(3)}-#{i}@example.com" }
  end

  trait :with_avatar do
    avatar { Rack::Test::UploadedFile.new(Raif::Engine.root.join("spec/fixtures/files/cultivate.png"), "image/png") }
  end
end
