# frozen_string_literal: true

Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v3 do
      namespace :store do
        scope :otp, controller: 'otp' do
          post :request, action: :request_otp
          post :verify, action: :verify
          post :resend, action: :resend
          post :fallback, action: :fallback
          post :status, action: :delivery_status
          patch 'customer/mobile', action: :update_mobile
        end
      end
    end
  end

  # Gupshup message-event callback (delivery failures trigger the email backup).
  post 'webhooks/gupshup', to: 'webhooks/gupshup#create', as: :gupshup_webhook

  namespace :admin do
    resource :otp_configuration, only: [:edit, :update] do
      post :test_whatsapp
    end
  end
end
