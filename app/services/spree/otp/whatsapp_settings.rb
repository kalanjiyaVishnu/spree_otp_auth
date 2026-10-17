# frozen_string_literal: true

module Spree
  module Otp
    # The one place the engine reads WhatsApp provider settings from.
    #
    # They live in the host app's per-store Notification::Setting (Admin →
    # Notification Settings → WhatsApp), next to the email and SMS providers.
    # Without that model (engine used elsewhere) WhatsApp is simply not set up.
    module WhatsappSettings
      class Unconfigured
        def whatsapp_provider = 'none'
        def gupshup_source_number = nil
        def gupshup_app_name = nil
        def gupshup_app_id = nil
        def gupshup_template_id = nil
        def effective_gupshup_template_name = 'verify_otp'
        def gupshup_api_key_present? = Spree::Otp::Provider::GupshupWhatsapp.api_key.present?
        def missing_whatsapp_requirements = ['WhatsApp provider (choose Gupshup)']
        def whatsapp_ready? = false
      end

      module_function

      def for(store)
        return Unconfigured.new unless store && defined?(::Notification::Setting)

        ::Notification::Setting.for_store(store) || Unconfigured.new
      end
    end
  end
end
