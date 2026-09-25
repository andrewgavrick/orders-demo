# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :v1, defaults: { format: :json } do
    resource :session, only: %i[create show destroy]
    resources :actors, only: %i[index show] do
      resources :orders, only: %i[index create]
      resources :transactions, only: :index
    end
    resources :orders, only: :show do
      post :complete, on: :member
      post :cancel, on: :member
    end
  end
end
