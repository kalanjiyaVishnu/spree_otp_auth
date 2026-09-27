# frozen_string_literal: true

module Spree
  module OtpUserDecorator
    def self.prepended(base)
      base.has_many :otp_attempts, class_name: 'Spree::OtpAttempt', dependent: :destroy

      base.validates :mobile_number,
                     uniqueness: { case_sensitive: false, allow_blank: true },
                     format: { with: /\A\+[1-9]\d{9,14}\z/, message: :invalid_phone_format, allow_blank: true }

      base.before_validation :normalize_auth_identifiers
    end

    def mobile_confirmed?
      respond_to?(:mobile_confirmed_at) && mobile_confirmed_at.present?
    end

    def confirm_mobile!(phone_or_timestamp = nil, timestamp = Time.current)
      if phone_or_timestamp.is_a?(String)
        normalized = normalize_phone(phone_or_timestamp)
        updates = { mobile_number: normalized }
        updates[:phone] = normalized if respond_to?(:phone=)
        updates[:mobile_confirmed_at] = timestamp if respond_to?(:mobile_confirmed_at)
        update!(updates)
      else
        ts = phone_or_timestamp || timestamp
        update_columns(mobile_confirmed_at: ts) if respond_to?(:mobile_confirmed_at)
      end
    end

    private

    def normalize_auth_identifiers
      self.email = email.to_s.strip.downcase.presence if respond_to?(:email)
      self.mobile_number = normalize_phone(mobile_number) if mobile_number.present?
      self.phone = mobile_number if respond_to?(:phone=) && mobile_number.present?
      self.auth_identifier = (auth_channel == 'mobile' ? mobile_number : email).presence if respond_to?(:auth_identifier=)
    end

    def normalize_phone(raw)
      digits = raw.to_s.gsub(/\D/, '')
      digits = "91#{digits}" if digits.length == 10
      digits.present? ? "+#{digits}" : nil
    end
  end

  Spree.user_class.prepend(OtpUserDecorator) if Spree.user_class
end
