# frozen_string_literal: true

module Spree
  module Otp
    class Resend
      prepend Spree::ServiceModule::Base

      def call(store:, identifier:, channel: nil, request_env: {})
        raw = identifier.to_s.strip
        normalized = raw.include?('@') ? raw.downcase : raw

        # Carry over staged mobile number from the most recent attempt if present
        latest_attempt = Spree::OtpAttempt.where(store: store).for_identifier(normalized).order(created_at: :desc).first
        staged_mobile = latest_attempt&.staged_mobile_number

        Spree::Otp::Generate.call(
          store: store,
          identifier: identifier,
          mobile_number: staged_mobile,
          channel: channel,
          request_env: request_env
        )
      end
    end
  end
end
