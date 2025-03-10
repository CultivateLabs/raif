# frozen_string_literal: true

FactoryBot.define do
  factory :raif_conversation_entry, class: "Raif::ConversationEntry" do
    sequence(:user_message){|i| "User message #{i} #{SecureRandom.hex(4)}" }
    started_at { Time.current }
    creator { raif_conversation.creator }

    trait :completed do
      sequence(:model_response_message){|i| "Model response #{i} #{SecureRandom.hex(4)}" }
      completed_at { Time.current }

      after(:create) do |entry|
        FB.create(
          :raif_conversation_entry_completion,
          raif_conversation_entry: entry,
          creator: entry.creator
        )
      end
    end
  end
end
