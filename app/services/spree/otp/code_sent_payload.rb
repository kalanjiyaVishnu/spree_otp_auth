# frozen_string_literal: true

module Spree
  module Otp
    # Builds the "code sent" response shared by request, resend and fallback
    # (CodeSent in specs/017-whatsapp-otp-marketing-consent/contracts/otp-api-v3.yaml).
    module CodeSentPayload
      module_function

      def build(attempt:, config:, auto_fallback: false)
        email_destination = Spree::Otp::Delivery.email_destination(attempt)
        sent_by_email = attempt.channel == 'email'
        target = sent_by_email ? email_destination : attempt.identifier
        child = attempt.link_email_attempt

        {
          requires_mobile: false,
          requires_email: false,
          requires_email_code: child.present?,
          channel: attempt.channel,
          masked_target: Spree::Otp::Identity.mask(target.to_s),
          masked_email: (child || sent_by_email) ? Spree::Otp::Identity.mask_email((child&.identifier || email_destination).to_s) : nil,
          auto_fallback: auto_fallback,
          otp_length: config.otp_length || 6,
          cooldown_seconds: config.resend_cooldown_seconds,
          fallback_available_after_seconds: config.fallback_delay_seconds,
          email_fallback_available: !sent_by_email && child.nil? && config.email_fallback_enabled? && email_destination.present?
        }
      end
    end
  end
end
