# frozen_string_literal: true

require 'jwt'
require 'securerandom'

module Spree
  module Otp
    class Verify
      prepend Spree::ServiceModule::Base

      # accept_marketing: nil when the news-and-offers box wasn't shown.
      def call(store:, identifier:, code:, email_code: nil, accept_marketing: nil, request_env: {})
        normalized_identifier, = Spree::Otp::Identity.normalize_identifier(identifier)
        return failure(:invalid_identifier, 'Invalid email or phone number format.') if normalized_identifier.blank?

        attempt = find_active_attempt(store, normalized_identifier)
        return failure(:invalid_otp, 'The entered code is incorrect or expired. Please try again.') unless attempt

        code_failure = check_code(attempt, code, :invalid_otp, 'The entered code is incorrect or expired. Please try again.')
        return code_failure if code_failure

        link_attempt = attempt.link_email_attempt
        if link_attempt
          return failure(:invalid_email_code, 'The code sent to your email is incorrect or expired.') if link_attempt.expired?

          email_failure = check_code(link_attempt, email_code, :invalid_email_code, 'The code sent to your email is incorrect or expired.')
          return email_failure if email_failure
        end

        user = nil
        ApplicationRecord.transaction do
          attempt.mark_verified!
          link_attempt&.mark_verified!
          user = resolve_user(attempt, normalized_identifier)
          attempt.update(user: user) if attempt.user_id.nil?
          Spree::Otp::MarketingConsent.call(user: user, store: store, accept: accept_marketing)
        end

        tokens = issue_tokens(user, request_env)

        success(
          user: user,
          token: tokens[:token],
          refresh_token: tokens[:refresh_token],
          attempt: attempt
        )
      end

      private

      # Returns a failure Result, or nil when the code matches.
      def check_code(attempt, submitted, error_code, message)
        if attempt.locked?
          return failure(:max_attempts_exceeded, 'Maximum verification attempts reached. Please request a new code.')
        end
        return nil if attempt.valid_code?(submitted)

        attempt.record_failed_attempt!
        return failure(:max_attempts_exceeded, 'Maximum verification attempts reached. Please request a new code.') if attempt.locked?

        failure(error_code, message)
      end

      def find_active_attempt(store, identifier)
        Spree::OtpAttempt.where(store: store, identifier: identifier).login.active
                         .order(created_at: :desc)
                         .first
      end

      def resolve_user(attempt, identifier)
        user = if Spree::Otp::Identity.email_identifier?(identifier)
                 find_or_create_email_user(identifier)
               else
                 attempt.user || find_or_create_mobile_user(identifier, attempt.staged_email)
               end

        changed = false
        if attempt.staged_mobile_number.present? && user.mobile_number != attempt.staged_mobile_number
          user.mobile_number = attempt.staged_mobile_number
          changed = true
        end
        # A mobile-first login finished with an email backup code doesn't prove
        # the phone. Email-first logins keep feature 010's behaviour.
        phone_unproven = attempt.channel == 'email' && !Spree::Otp::Identity.email_identifier?(identifier)
        if !phone_unproven && user.mobile_number.present? && user.respond_to?(:mobile_confirmed_at=) &&
           (attempt.staged_mobile_number.present? || !Spree::Otp::Identity.email_identifier?(identifier))
          user.mobile_confirmed_at ||= Time.current
          changed = true
        end
        if attempt.staged_email.present? && !Spree::Otp::Identity.real_email?(user.email)
          user.email = attempt.staged_email
          changed = true
        end
        user.save!(validate: false) if changed
        user
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

      def find_or_create_mobile_user(mobile, staged_email = nil)
        user = Spree.user_class.find_by(mobile_number: mobile)
        return user if user

        placeholder_email = Spree::Otp::Identity.synthetic_email_for(mobile)
        user = Spree.user_class.find_by('LOWER(email) = ?', placeholder_email)
        return user if user

        user = Spree.user_class.new(
          email: staged_email.presence || placeholder_email,
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
