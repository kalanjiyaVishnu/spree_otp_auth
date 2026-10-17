# frozen_string_literal: true

module Spree
  module Otp
    # Picks the provider for a channel and the destination for an attempt.
    module Delivery
      module_function

      def provider_for(channel, store)
        case channel.to_s
        when 'whatsapp' then Spree::Otp::Provider::GupshupWhatsapp.new(store)
        when 'mobile' then Spree::Otp::Provider::Msg91Sms.new(store)
        else Spree::Otp::Provider::Email.new(store)
        end
      end

      # Where an email code for this attempt would go: the identifier itself for
      # email-first logins, else the staged email, else the account's real email.
      def email_destination(attempt)
        return attempt.identifier if Spree::Otp::Identity.email_identifier?(attempt.identifier)
        return attempt.staged_email if attempt.staged_email.present?

        email = attempt.user&.email
        Spree::Otp::Identity.real_email?(email) ? email : nil
      end

      def destination_for(attempt)
        attempt.channel == 'email' ? email_destination(attempt) : attempt.identifier
      end
    end
  end
end
