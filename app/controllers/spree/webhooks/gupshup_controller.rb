# frozen_string_literal: true

module Spree
  module Webhooks
    # Receives Gupshup message events. Gupshup only learns that a number isn't
    # on WhatsApp after accepting the send, so a "failed" event is what triggers
    # the automatic email backup for most failures.
    #
    # Gupshup callbacks are unsigned; the URL carries GUPSHUP_WEBHOOK_SECRET as
    # a query param (filtered from logs by filter_parameters):
    #   POST /webhooks/gupshup?secret=<GUPSHUP_WEBHOOK_SECRET>
    class GupshupController < ActionController::API
      before_action :verify_secret

      def create
        event = request.request_parameters.presence || parse_body
        handle_event(event) if event.is_a?(Hash)
        head :ok
      end

      private

      def verify_secret
        expected = ENV['GUPSHUP_WEBHOOK_SECRET'].to_s
        given = params[:secret].to_s
        return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, given)

        head :not_found
      end

      def parse_body
        JSON.parse(request.raw_post.presence || '{}')
      rescue JSON::ParserError
        nil
      end

      def handle_event(event)
        return unless event['type'] == 'message-event'

        payload = event['payload'].is_a?(Hash) ? event['payload'] : {}
        return unless payload['type'] == 'failed'

        message_ids = [payload['gsId'], payload['id']].compact_blank
        return if message_ids.empty?

        attempt = Spree::OtpAttempt.login.find_by(provider_message_id: message_ids, channel: 'whatsapp')
        return if attempt.nil? || attempt.verified? || attempt.expired? || attempt.delivery_status == 'fallback_sent'

        reason = payload.dig('payload', 'reason').to_s.truncate(120)
        Rails.logger.info("[Gupshup] Message #{attempt.provider_message_id} failed for OTP attempt #{attempt.prefixed_id}")

        config = attempt.store.effective_otp_configuration
        result = if config.email_fallback_enabled?
                   Spree::Otp::Fallback.call(store: attempt.store, attempt: attempt, reason: reason, enforce_cooldown: false)
                 end

        return if result&.success?

        attempt.update_columns(delivery_status: 'failed', fallback_reason: reason.presence)
      end
    end
  end
end
