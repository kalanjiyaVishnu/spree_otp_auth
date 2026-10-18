# frozen_string_literal: true

module SpreeOtpAuth
  class Engine < ::Rails::Engine
    engine_name 'spree_otp_auth'

    config.generators do |g|
      g.test_framework :rspec
    end

    # The verify endpoint takes the one-time code as `code`; keep it out of the
    # "Parameters:" log lines. Exact match so promo_code, country_code, etc.
    # stay readable.
    initializer 'spree_otp_auth.filter_parameters' do |app|
      app.config.filter_parameters += [/\Acode\z/]
    end

    # OTP codes go out through spree_notification_providers; the code's
    # provider-side template is entered per provider under "Login code".
    initializer 'spree_otp_auth.message_types' do
      SpreeNotificationProviders.register_message_type :otp_code,
                                                       label: 'Login code', channels: %i[email sms whatsapp]
    end

    # A provider that reports a code as failed after accepting it (e.g. a
    # Gupshup "failed" webhook) triggers the email backup. Messages sent before
    # spree_notification_providers have no delivery row, so the webhook asks
    # this resolver which store owns the message id.
    config.after_initialize do
      Spree.subscribers << Spree::Otp::DeliveryFailedSubscriber
      SpreeNotificationProviders.register_message_resolver(:gupshup) do |provider_message_id|
        Spree::OtpAttempt.find_by(provider_message_id: provider_message_id, channel: 'whatsapp')&.store
      end
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
