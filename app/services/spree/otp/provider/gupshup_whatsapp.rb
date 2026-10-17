# frozen_string_literal: true

require 'net/http'
require 'json'
require 'securerandom'

module Spree
  module Otp
    module Provider
      # Sends the login code as a WhatsApp template message through Gupshup.
      #
      # Gupshup's send endpoint takes the template UUID, so the configured
      # template name (default "verify_otp") is resolved through the app's
      # template list and cached. A 2xx "submitted" reply only means Gupshup
      # accepted the message; delivery failures arrive later on the webhook
      # (see Spree::Webhooks::GupshupController).
      class GupshupWhatsapp < Base
        HOST = 'api.gupshup.io'
        SEND_PATH = '/wa/api/v1/template/msg'
        TIMEOUT_SECONDS = 5
        TEMPLATE_CACHE_TTL = 12.hours
        TEST_CODE = '123456'

        def self.api_key
          ENV['GUPSHUP_API_KEY'].presence
        end

        def self.template_cache_key(store)
          "otp:gupshup_template:#{store.id}"
        end

        def self.clear_template_cache(store)
          Rails.cache.delete(template_cache_key(store))
        end

        def send_otp(identifier:, code:, metadata: {})
          destination = identifier.to_s.gsub(/\D/, '')
          return failure('provider_not_configured') unless settings.whatsapp_provider == 'gupshup'

          key = self.class.api_key

          if key.blank?
            return failure('provider_not_configured') if Rails.env.production?

            Rails.logger.info("[Gupshup] GUPSHUP_API_KEY missing; simulating WhatsApp OTP for store #{store.id}")
            return Result.new(success: true, channel: 'whatsapp', message_id: "sim-gs-#{SecureRandom.hex(8)}")
          end

          return failure('provider_not_configured') if settings.gupshup_source_number.blank? || settings.gupshup_app_name.blank?

          template_id = resolve_template_id(key)
          return failure('template_not_found') if template_id.blank?

          response = post_template(key, destination, template_id, code)
          body = parse_json(response.body)

          if response.is_a?(Net::HTTPSuccess) && body['status'] == 'submitted'
            Result.new(success: true, channel: 'whatsapp', message_id: body['messageId'])
          else
            reason = response.is_a?(Net::HTTPSuccess) ? "status #{body['status'].presence || 'unknown'}" : "HTTP #{response.code}"
            Rails.logger.warn("[Gupshup] Send rejected for store #{store.id}: #{reason}")
            failure(reason)
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          Rails.logger.warn("[Gupshup] Timed out sending OTP for store #{store.id}")
          failure('timeout')
        rescue StandardError => e
          Rails.logger.error("[Gupshup] #{e.class} sending OTP for store #{store.id}")
          failure(e.class.name)
        end

        # Admin "Send test message": real send with a fixed, non-secret code.
        def test_send(phone:)
          normalized = Spree::Otp::Identity.normalize_phone(phone)
          return failure('invalid_phone') unless Spree::Otp::Identity.valid_phone?(normalized)

          send_otp(identifier: normalized, code: TEST_CODE)
        end

        private

        # Provider details come from Notification Settings → WhatsApp.
        def settings
          @settings ||= Spree::Otp::WhatsappSettings.for(store)
        end

        def failure(reason)
          Result.new(success: false, channel: 'whatsapp', error_message: reason)
        end

        def resolve_template_id(key)
          return settings.gupshup_template_id if settings.gupshup_template_id.present?
          return nil if settings.gupshup_app_id.blank?

          name = settings.effective_gupshup_template_name
          cache_key = self.class.template_cache_key(store)
          cached = Rails.cache.read(cache_key)
          return cached[:id] if cached.is_a?(Hash) && cached[:name] == name && cached[:app_id] == settings.gupshup_app_id

          id = lookup_template_id(key, name)
          Rails.cache.write(cache_key, { name: name, app_id: settings.gupshup_app_id, id: id }, expires_in: TEMPLATE_CACHE_TTL) if id
          id
        end

        def lookup_template_id(key, name)
          path = "/wa/app/#{ERB::Util.url_encode(settings.gupshup_app_id)}/template?templateStatus=APPROVED"
          request = Net::HTTP::Get.new(path)
          request['apikey'] = key

          response = perform(request)
          return nil unless response.is_a?(Net::HTTPSuccess)

          templates = Array(parse_json(response.body)['templates'])
          match = templates.find { |t| t['elementName'] == name && t['status'].to_s.casecmp('APPROVED').zero? }
          match&.dig('id')
        end

        def post_template(key, destination, template_id, code)
          request = Net::HTTP::Post.new(SEND_PATH)
          request['apikey'] = key
          request['Content-Type'] = 'application/x-www-form-urlencoded'
          request.body = URI.encode_www_form(
            'channel' => 'whatsapp',
            'source' => settings.gupshup_source_number,
            'destination' => destination,
            'src.name' => settings.gupshup_app_name,
            'template' => { id: template_id, params: [code.to_s] }.to_json
          )
          perform(request)
        end

        def perform(request)
          Net::HTTP.start(HOST, 443, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
            http.request(request)
          end
        end

        def parse_json(raw)
          JSON.parse(raw.to_s)
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
