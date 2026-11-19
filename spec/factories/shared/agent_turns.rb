# frozen_string_literal: true

FactoryBot.define do
  factory :raif_agent_turn, class: "Raif::AgentTurn" do
    raif_agent { association(:raif_native_tool_calling_agent) }
    sequence(:iteration) { |i| i }
  end
end
