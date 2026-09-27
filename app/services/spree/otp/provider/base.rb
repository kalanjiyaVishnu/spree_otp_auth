# frozen_string_literal: true

module Spree
  module Otp
    class DeliveryError < StandardError; end

    module Provider
      class Base
        attr_reader :store, :config

        def initialize(store)
          @store = store
          @config = store.otp_configuration || Spree::OtpConfiguration.default_for(store)
        end

        def send_otp(identifier:, code:, metadata: {})
          raise NotImplementedError, "#{self.class.name}#send_otp must be implemented"
        end

        def resend_otp(identifier:, code:, metadata: {})
          send_otp(identifier: identifier, code: code, metadata: metadata)
        end
      end

      class Result
        attr_reader :success, :channel, :message_id, :error_message

        def initialize(success:, channel:, message_id: nil, error_message: nil)
          @success = success
          @channel = channel
          @message_id = message_id
          @error_message = error_message
        end

        def success?
          @success == true
        end

        def failure?
          !success?
        end
      end
    end
  end
end
