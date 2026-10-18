# frozen_string_literal: true

module Spree
  module Otp
    # Sends login codes and picks where an attempt's code goes.
    #
    # SMS and WhatsApp codes go through spree_notification_providers, so the
    # store's providers for that channel are tried in priority order. Email
    # codes are rendered by Spree::OtpMailer and delivered later by the
    # app's mailer (which itself can route through the providers).
    module Delivery
      # :sent    - a provider accepted the code
      # :unknown - it may have gone out; never resend or switch channel for it
      # :failed  - no provider can have sent it; safe to fall back
      Outcome = Struct.new(:status, :message_id, :message_ref, :error_message, keyword_init: true) do
        def sent? = status == :sent
        def unknown? = status == :unknown
        def failed? = status == :failed
      end

      module_function

      # OTP channel names predate the provider gem: 'mobile' means SMS.
      def provider_channel(channel)
        channel.to_s == 'mobile' ? :sms : channel.to_sym
      end

      def deliver(channel:, store:, destination:, code:, expiry_minutes:, attempt: nil)
        return send_email(store: store, to: destination, code: code, expiry_minutes: expiry_minutes) if channel.to_s == 'email'

        message = SpreeNotificationProviders::Message.new(
          channel: provider_channel(channel), type: :otp_code, kind: :otp, to: destination,
          code: code, expiry_minutes: expiry_minutes, source: attempt
        )
        result = SpreeNotificationProviders.deliver(store: store, message: message)
        status = if result.success? then :sent
                 elsif result.retryable? then :failed
                 else :unknown
                 end
        Outcome.new(
          status: status, message_id: result.provider_message_id, message_ref: result.message_ref,
          error_message: (result.reasons.join('; ').presence || result.outcome.to_s if status == :failed)
        )
      end

      def send_email(store:, to:, code:, expiry_minutes:)
        mail = Spree::OtpMailer.send_otp(store: store, to: to, code: code, expiry_minutes: expiry_minutes)
        mail.deliver_later
        Outcome.new(status: :sent, message_id: mail.message_id)
      rescue StandardError => e
        Rails.logger.error("[SpreeOtpAuth] email code not queued: #{e.class}: #{e.message}")
        Outcome.new(status: :failed, error_message: e.class.name)
      end

      # Whether the store can send login codes on this OTP channel.
      def ready?(store, channel)
        return true if channel.to_s == 'email'

        SpreeNotificationProviders.ready_for?(store, provider_channel(channel), :otp_code)
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
