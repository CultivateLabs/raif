# frozen_string_literal: true

FactoryBot.define do
  factory :raif_agent, class: "Raif::Agent" do
    task { "What is Jimmy Buffet's birthday?" }
    available_model_tools { ["Raif::ModelTools::WikipediaSearch", "Raif::ModelTools::FetchUrl"] }
    creator { FB.create(:raif_test_user) }
  end

  factory :raif_native_tool_calling_agent, parent: :raif_agent, class: "Raif::Agents::NativeToolCallingAgent" do
  end
end
