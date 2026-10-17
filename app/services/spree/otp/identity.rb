# frozen_string_literal: true

module Spree
  module Otp
    # Phone/email normalisation and masking shared by the OTP services and
    # controllers. Mobile-created accounts carry a synthetic
    # "<digits>@guest.ontodi.local" email, which counts as "no email".
    module Identity
      PHONE_FORMAT = /\A\+[1-9]\d{9,14}\z/
      SYNTHETIC_EMAIL_DOMAIN = '@guest.ontodi.local'

      module_function

      def normalize_phone(raw)
        digits = raw.to_s.gsub(/\D/, '')
        return nil if digits.length < 10

        digits = "91#{digits}" if digits.length == 10
        "+#{digits}"
      end

      def valid_phone?(phone)
        phone.to_s.match?(PHONE_FORMAT)
      end

      def normalize_email(raw)
        raw.to_s.strip.downcase.presence
      end

      def valid_email?(email)
        email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
      end

      def email_identifier?(identifier)
        identifier.to_s.include?('@')
      end

      def real_email?(email)
        email.present? && !email.to_s.downcase.end_with?(SYNTHETIC_EMAIL_DOMAIN)
      end

      def synthetic_email_for(mobile)
        "#{mobile.to_s.gsub(/\D/, '')}#{SYNTHETIC_EMAIL_DOMAIN}"
      end

      # Returns [normalized, 'email' | 'mobile'] or [nil, nil].
      def normalize_identifier(identifier)
        raw = identifier.to_s.strip
        return [normalize_email(raw), 'email'] if email_identifier?(raw)

        phone = normalize_phone(raw)
        phone ? [phone, 'mobile'] : [nil, nil]
      end

      def mask_email(email)
        user_part, domain = email.to_s.split('@', 2)
        return email.to_s if user_part.blank? || domain.blank?

        masked_user = user_part.length <= 2 ? "#{user_part[0]}***" : "#{user_part[0]}***#{user_part[-1]}"
        "#{masked_user}@#{domain}"
      end

      def mask_phone(phone)
        digits = phone.to_s.gsub(/\D/, '')
        return phone.to_s if digits.length < 10

        country_code = digits[0..-11]
        "+#{country_code.presence || '91'} #{digits[-10..-9]}*** **#{digits[-3..]}"
      end

      def mask(identifier)
        email_identifier?(identifier) ? mask_email(identifier) : mask_phone(identifier)
      end
    end
  end
end
