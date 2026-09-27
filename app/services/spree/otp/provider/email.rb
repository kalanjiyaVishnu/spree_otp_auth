# frozen_string_literal: true

module Spree
  module Otp
    module Provider
      class Email < Base
        def send_otp(identifier:, code:, metadata: {})
          expiry_minutes = metadata[:expiry_minutes] || ((config.otp_expiry_seconds || 600) / 60)

          mail = Spree::OtpMailer.send_otp(
            store: store,
            to: identifier,
            code: code,
            expiry_minutes: expiry_minutes
          )
          mail.deliver_later

          Result.new(
            success: true,
            channel: 'email',
            message_id: mail.message_id
          )
        rescue StandardError => e
          Result.new(
            success: false,
            channel: 'email',
            error_message: e.message
          )
        end
      end
    end
  end
end
