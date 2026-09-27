# frozen_string_literal: true

Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    namespace :v3 do
      namespace :store do
        scope :otp, controller: 'otp' do
          post :request, action: :request_otp
          post :verify, action: :verify
          post :resend, action: :resend
          post :whatsapp, action: :whatsapp
          patch 'customer/mobile', action: :update_mobile
        end
      end
    end
  end

  namespace :admin do
    resource :otp_configuration, only: [:edit, :update]
  end
end
