# frozen_string_literal: true

module Spree
  module Otp
    # Sends a fresh login code by email in place of an attempt's WhatsApp code.
    #
    # Used for the automatic backup (immediate send failure in Generate, or a
    # Gupshup "failed" webhook) and for the customer's "Send code by email
    # instead" link. Only the new code is valid afterwards.
    class Fallback
      prepend Spree::ServiceModule::Base

      # discard_original: destroy the original attempt instead of expiring it
      #   (its WhatsApp send never went out, so it shouldn't count toward limits).
      def call(store:, attempt:, reason: nil, enforce_cooldown: true, discard_original: false)
        config = store.effective_otp_configuration
        return failure(:email_fallback_disabled, 'Email codes are not available right now.') unless config.email_fallback_enabled?

        # Linking a number to an email-only account needs the WhatsApp code as
        # proof of the phone; an email code can't replace it.
        if attempt.link_email_attempt.present?
          return failure(:email_fallback_disabled, 'Please use the code sent on WhatsApp to link this number.')
        end

        email = Spree::Otp::Delivery.email_destination(attempt)
        unless Spree::Otp::Identity.real_email?(email)
          return failure(:no_email_on_account, 'There is no email on this account to send a code to.')
        end

        limiter = Spree::Otp::RateLimiter.new(store: store, identifier: attempt.identifier)
        if enforce_cooldown
          allowed, reason_code, retry_after = limiter.check_dispatch_allowed(config.resend_cooldown_seconds)
          unless allowed
            if reason_code == :hourly_limit_exceeded
              return failure(:hourly_limit_exceeded, 'Hourly limit of 5 codes exceeded. Please try again later.')
            end

            return failure(:cooldown_active, { message: "Please wait #{retry_after} seconds before requesting another code.", retry_after_seconds: retry_after })
          end
        elsif limiter.hourly_limit_exceeded?
          return failure(:hourly_limit_exceeded, 'Hourly limit of 5 codes exceeded. Please try again later.')
        end

        code = Spree::Otp::Generate.generate_code(config.otp_length || 6)
        salt = Spree::OtpAttempt.generate_salt
        new_attempt = nil

        ApplicationRecord.transaction do
          new_attempt = Spree::OtpAttempt.create!(
            store: store,
            user: attempt.user,
            identifier: attempt.identifier,
            channel: 'email',
            purpose: 'login',
            code_digest: Spree::OtpAttempt.digest(code, salt),
            salt: salt,
            staged_mobile_number: attempt.staged_mobile_number,
            staged_email: attempt.staged_email,
            delivery_status: 'pending',
            expires_at: (config.otp_expiry_seconds || 600).seconds.from_now,
            ip_address: attempt.ip_address,
            user_agent: attempt.user_agent
          )

          if discard_original
            attempt.destroy!
          else
            attempt.expire!
            attempt.update_columns(delivery_status: 'fallback_sent', fallback_reason: reason.to_s.truncate(120).presence)
          end
        end

        result = Spree::Otp::Provider::Email.new(store).send_otp(
          identifier: email,
          code: code,
          metadata: { expiry_minutes: ((config.otp_expiry_seconds || 600) / 60) }
        )

        if result.failure?
          new_attempt.update_columns(delivery_status: 'failed', fallback_reason: result.error_message.to_s.truncate(120))
          return failure(:delivery_failed, 'Failed to send the code by email.')
        end

        new_attempt.update_columns(delivery_status: 'submitted', provider_message_id: result.message_id)
        success(attempt: new_attempt.reload)
      end
    end
  end
end
