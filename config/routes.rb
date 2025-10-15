# frozen_string_literal: true

Raif::Engine.routes.draw do
  resources :conversations,
    only: [:index, :show],
    controller: "/#{Raif.config.conversations_controller.constantize.controller_path}" do
    resources :conversation_entries,
      only: [:new, :create],
      as: :entries,
      path: "entries",
      controller: "/#{Raif.config.conversation_entries_controller.constantize.controller_path}"
  end

  namespace :admin do
    root to: redirect("admin/model_completions")
    resources :stats, only: [:index]

    namespace :stats do
      resources :tasks, only: [:index]
      resources :model_tool_invocations, only: [:index]
    end

    resources :tasks, only: [:index, :show]
    resources :conversations, only: [:index, :show]
    resources :model_completions, only: [:index, :show]
    resources :agents, only: [:index, :show]
    resources :model_tool_invocations, only: [:index, :show]
    resources :configurations, only: [:index]
  end
end
