# frozen_string_literal: true

module Spree
  module Otp
    class Resend
      prepend Spree::ServiceModule::Base

      # Resends on the latest attempt's channel (so a code that already moved to
      # email stays on email), carrying over whatever was collected on screen.
      def call(store:, identifier:, channel: nil, request_env: {})
        normalized, = Spree::Otp::Identity.normalize_identifier(identifier)
        normalized ||= identifier.to_s.strip

        latest_attempt = Spree::OtpAttempt.where(store: store).login.for_identifier(normalized).order(created_at: :desc).first

        Spree::Otp::Generate.call(
          store: store,
          identifier: identifier,
          mobile_number: latest_attempt&.staged_mobile_number,
          email: latest_attempt&.staged_email || latest_attempt&.link_email_attempt&.identifier,
          channel: channel.presence || latest_attempt&.channel,
          request_env: request_env
        )
      end
    end
  end
end
