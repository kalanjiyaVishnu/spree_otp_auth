# frozen_string_literal: true

require 'securerandom'

module Spree
  module Otp
    class Generate
      prepend Spree::ServiceModule::Base

      def call(store:, identifier:, mobile_number: nil, channel: nil, request_env: {})
        normalized_identifier, detected_channel = normalize_identifier(identifier)
        return failure(:invalid_identifier, 'Invalid email or phone number format.') if normalized_identifier.blank?

        config = store.respond_to?(:effective_otp_configuration) ? store.effective_otp_configuration : Spree::OtpConfiguration.default_for(store)

        user = find_user(normalized_identifier)

        # Adaptive progressive disclosure:
        # Check if customer has a registered mobile number
        has_mobile = user&.mobile_number.present?
        staged_mobile = nil

        if !has_mobile
          if mobile_number.blank?
            return success(
              requires_mobile: true,
              message: 'Mobile number is required to continue.'
            )
          else
            normalized_mobile = normalize_phone(mobile_number)
            if normalized_mobile.blank? || normalized_mobile !~ /\A\+[1-9]\d{9,14}\z/
              return failure(:invalid_phone, 'Invalid mobile phone number format.')
            end

            existing_mobile_user = Spree.user_class.find_by(mobile_number: normalized_mobile)
            if existing_mobile_user && existing_mobile_user.id != user&.id
              return failure(:phone_already_registered, 'This mobile number is already linked to another account.')
            end

            staged_mobile = normalized_mobile
          end
        end

        rate_limiter = Spree::Otp::RateLimiter.new(store: store, identifier: normalized_identifier)
        allowed, reason, retry_after = rate_limiter.check_dispatch_allowed(config.resend_cooldown_seconds)

        unless allowed
          if reason == :hourly_limit_exceeded
            return failure(:hourly_limit_exceeded, 'Hourly limit of 5 codes exceeded. Please try again later.')
          else
            return failure(:cooldown_active, { message: "Please wait #{retry_after} seconds before requesting another code.", retry_after_seconds: retry_after })
          end
        end

        active_channel = channel.presence || (detected_channel == 'email' ? 'email' : config.active_channel)

        otp_length = config.otp_length || 6
        code = generate_code(otp_length)
        salt = Spree::OtpAttempt.generate_salt
        code_digest = Spree::OtpAttempt.digest(code, salt)
        expires_at = (config.otp_expiry_seconds || 600).seconds.from_now

        attempt = Spree::OtpAttempt.create!(
          store: store,
          user: user,
          identifier: normalized_identifier,
          channel: active_channel,
          code_digest: code_digest,
          salt: salt,
          staged_mobile_number: staged_mobile,
          expires_at: expires_at,
          ip_address: request_env[:ip_address],
          user_agent: request_env[:user_agent]&.truncate(255)
        )

        provider = resolve_provider(active_channel, store)
        dispatch_result = provider.send_otp(
          identifier: normalized_identifier,
          code: code,
          metadata: { expiry_minutes: ((config.otp_expiry_seconds || 600) / 60) }
        )

        if dispatch_result.failure?
          attempt.destroy # Clean up unsent attempt so cooldown isn't unfairly triggered
          return failure(:delivery_failed, dispatch_result.error_message || 'Failed to deliver passcode.')
        end

        success(
          requires_mobile: false,
          channel: active_channel,
          masked_target: mask_target(normalized_identifier, active_channel),
          otp_length: otp_length,
          cooldown_seconds: config.resend_cooldown_seconds,
          fallback_available_after_seconds: config.fallback_delay_seconds
        )
      end

      private

      def normalize_phone(raw)
        digits = raw.to_s.gsub(/\D/, '')
        return nil if digits.length < 10
        digits = "91#{digits}" if digits.length == 10
        "+#{digits}"
      end

      def normalize_identifier(identifier)
        raw = identifier.to_s.strip
        if raw.include?('@')
          [raw.downcase, 'email']
        else
          digits = raw.gsub(/\D/, '')
          return [nil, nil] if digits.length < 10
          digits = "91#{digits}" if digits.length == 10
          ["+#{digits}", 'mobile']
        end
      end

      def generate_code(length)
        min = 10**(length - 1)
        max = (10**length) - 1
        SecureRandom.random_number(min..max).to_s
      end

      def find_user(identifier)
        if identifier.include?('@')
          Spree.user_class.find_by('LOWER(email) = ?', identifier)
        else
          Spree.user_class.find_by(mobile_number: identifier)
        end
      end

      def resolve_provider(channel, store)
        case channel.to_s
        when 'email'
          Spree::Otp::Provider::Email.new(store)
        when 'mobile'
          if defined?(Spree::Otp::Provider::Msg91Sms)
            Spree::Otp::Provider::Msg91Sms.new(store)
          else
            Spree::Otp::Provider::Email.new(store)
          end
        when 'whatsapp'
          if defined?(Spree::Otp::Provider::Msg91Whatsapp)
            Spree::Otp::Provider::Msg91Whatsapp.new(store)
          else
            Spree::Otp::Provider::Email.new(store)
          end
        else
          Spree::Otp::Provider::Email.new(store)
        end
      end

      def mask_target(identifier, channel)
        if channel == 'email' || identifier.include?('@')
          user_part, domain = identifier.split('@', 2)
          if user_part.length <= 2
            masked_user = "#{user_part[0]}***"
          else
            masked_user = "#{user_part[0]}***#{user_part[-1]}"
          end
          "#{masked_user}@#{domain}"
        else
          digits = identifier.gsub(/\D/, '')
          if digits.length >= 10
            country_code = digits[0..-11]
            prefix = digits[-10..-9]
            last3 = digits[-3..-1]
            "+#{country_code.presence || '91'} #{prefix}*** **#{last3}"
          else
            identifier
          end
        end
      end
    end
  end
end
