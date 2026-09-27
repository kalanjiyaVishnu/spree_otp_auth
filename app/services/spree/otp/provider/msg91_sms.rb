# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Spree
  module Otp
    module Provider
      class Msg91Sms < Base
        MSG91_OTP_ENDPOINT = 'https://control.msg91.com/api/v5/otp'

        def send_otp(identifier:, code:, metadata: {})
          auth_key = config.effective_msg91_auth_key
          template_id = config.effective_msg91_sms_template_id
          mobile = identifier.to_s.gsub(/\D/, '')

          if auth_key.blank? || template_id.blank?
            Rails.logger.warn("[MSG91 SMS] Missing auth_key or template_id for store #{store.id}. Simulating delivery in #{Rails.env}.")
            return Result.new(success: true, channel: 'mobile', message_id: "sim-#{SecureRandom.hex(8)}")
          end

          uri = URI(MSG91_OTP_ENDPOINT)
          params = {
            template_id: template_id,
            mobile: mobile,
            otp: code,
            otp_expiry: metadata[:expiry_minutes] || 10
          }
          params[:sender] = config.effective_msg91_sender_id if config.effective_msg91_sender_id.present?
          uri.query = URI.encode_www_form(params)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.open_timeout = 5
          http.read_timeout = 5

          request = Net::HTTP::Post.new(uri.request_uri)
          request['authkey'] = auth_key
          request['Content-Type'] = 'application/json'

          response = http.request(request)
          body = JSON.parse(response.body) rescue {}

          if response.is_a?(Net::HTTPSuccess) && (body['type'] == 'success' || body['message_id'].present?)
            Result.new(success: true, channel: 'mobile', message_id: body['message_id'] || body['request_id'])
          else
            Result.new(success: false, channel: 'mobile', error_message: body['message'] || "HTTP #{response.code}")
          end
        rescue StandardError => e
          Rails.logger.error("[MSG91 SMS Error] #{e.class}: #{e.message}")
          Result.new(success: false, channel: 'mobile', error_message: e.message)
        end
      end
    end
  end
end
