# frozen_string_literal: true

require 'jwt'
require 'securerandom'

module Spree
  module Otp
    class Verify
      prepend Spree::ServiceModule::Base

      def call(store:, identifier:, code:, request_env: {})
        normalized_identifier = normalize_identifier(identifier)
        return failure(:invalid_identifier, 'Invalid email or phone number format.') if normalized_identifier.blank?

        attempt = find_active_attempt(store, normalized_identifier)
        return failure(:invalid_otp, 'The entered code is incorrect or expired. Please try again.') unless attempt

        if attempt.locked?
          return failure(:max_attempts_exceeded, 'Maximum verification attempts reached. Please request a new code.')
        end

        unless attempt.valid_code?(code)
          attempt.record_failed_attempt!
          if attempt.locked?
            return failure(:max_attempts_exceeded, 'Maximum verification attempts reached. Please request a new code.')
          else
            return failure(:invalid_otp, 'The entered code is incorrect or expired. Please try again.')
          end
        end

        attempt.mark_verified!
        user = find_or_create_user(normalized_identifier)
        if attempt.staged_mobile_number.present?
          user.mobile_number = attempt.staged_mobile_number
          user.mobile_confirmed_at = Time.current if user.respond_to?(:mobile_confirmed_at=)
          user.save!(validate: false)
        end
        attempt.update(user: user) if attempt.user_id.nil?

        tokens = issue_tokens(user, request_env)

        success(
          user: user,
          token: tokens[:token],
          refresh_token: tokens[:refresh_token],
          attempt: attempt
        )
      end

      private

      def normalize_identifier(identifier)
        raw = identifier.to_s.strip
        if raw.include?('@')
          raw.downcase
        else
          digits = raw.gsub(/\D/, '')
          return nil if digits.blank?
          digits = "91#{digits}" if digits.length == 10
          "+#{digits}"
        end
      end

      def find_active_attempt(store, identifier)
        Spree::OtpAttempt.where(store: store, identifier: identifier, verified_at: nil)
                         .where('expires_at > ?', Time.current)
                         .order(created_at: :desc)
                         .first
      end

      def find_or_create_user(identifier)
        if identifier.include?('@')
          find_or_create_email_user(identifier)
        else
          find_or_create_mobile_user(identifier)
        end
      end

      def find_or_create_email_user(email)
        user = Spree.user_class.find_by('LOWER(email) = ?', email)
        return user if user

        user = Spree.user_class.new(
          email: email,
          auth_identifier: email,
          auth_channel: 'email',
          password: SecureRandom.hex(16)
        )
        user.save!(validate: false)
        user
      end

      def find_or_create_mobile_user(mobile)
        user = Spree.user_class.find_by(mobile_number: mobile)
        return user if user

        digits = mobile.gsub(/\D/, '')
        placeholder_email = "#{digits}@guest.ontodi.local"
        user = Spree.user_class.find_by('LOWER(email) = ?', placeholder_email)
        return user if user

        user = Spree.user_class.new(
          email: placeholder_email,
          mobile_number: mobile,
          auth_identifier: mobile,
          auth_channel: 'mobile',
          password: SecureRandom.hex(16)
        )
        user.save!(validate: false)
        user
      end

      def issue_tokens(user, request_env)
        env = {
          ip_address: request_env[:ip_address],
          user_agent: request_env[:user_agent]&.truncate(255)
        }
        refresh_token = Spree::RefreshToken.create_for(user, request_env: env)
        jwt = generate_jwt(user)

        {
          token: jwt,
          refresh_token: refresh_token.token
        }
      end

      def generate_jwt(user, expiration: 30.days.to_i)
        payload = {
          user_id: user.id,
          user_type: determine_user_type(user),
          jti: SecureRandom.uuid,
          iss: 'spree',
          aud: 'store_api',
          exp: Time.current.to_i + expiration
        }
        JWT.encode(payload, jwt_secret, 'HS256')
      end

      def determine_user_type(user)
        if defined?(Spree.admin_user_class) && user.is_a?(Spree.admin_user_class)
          'admin'
        else
          'customer'
        end
      end

      def jwt_secret
        Spree::Api::Config[:jwt_secret_key].presence ||
          Rails.application.credentials.jwt_secret_key ||
          ENV['JWT_SECRET_KEY'] ||
          Rails.application.secret_key_base
      end
    end
  end
end
