# frozen_string_literal: true

module Spree
  module Otp
    # A provider accepted a login code, then reported it as failed (e.g. the
    # number is not on WhatsApp). Sends the code by email when the backup is
    # on; otherwise marks the attempt failed.
    class DeliveryFailedSubscriber < Spree::Subscriber
      subscribes_to 'notification.delivery_failed', async: false

      def call(event)
        payload = event.payload.to_h.stringify_keys
        attempt = find_attempt(payload)
        return if attempt.nil? || attempt.verified? || attempt.expired? || attempt.delivery_status == 'fallback_sent'

        reason = payload['reason'].to_s.truncate(120)
        Rails.logger.info("[SpreeOtpAuth] Code #{attempt.provider_message_id} failed for OTP attempt #{attempt.prefixed_id}")

        config = attempt.store.effective_otp_configuration
        result = if config.email_fallback_enabled?
                   Spree::Otp::Fallback.call(store: attempt.store, attempt: attempt, reason: reason, enforce_cooldown: false)
                 end
        return if result&.success?

        attempt.update_columns(delivery_status: 'failed', fallback_reason: reason.presence)
      end

      private

      def find_attempt(payload)
        scope = Spree::OtpAttempt.login.where(store_id: payload['store_id'])
        if payload['delivery_id'].present?
          delivery = Spree::NotificationDelivery.find_by(id: payload['delivery_id'])
          by_ref = scope.find_by(delivery_message_ref: delivery.message_ref) if delivery
          return by_ref if by_ref
        end
        return nil if payload['provider_message_id'].blank?

        scope.find_by(provider_message_id: payload['provider_message_id'])
      end
    end
  end
end
