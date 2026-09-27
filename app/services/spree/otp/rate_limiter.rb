# frozen_string_literal: true

module Spree
  module Otp
    class RateLimiter
      MAX_HOURLY_DISPATCHES = 5
      MAX_FAILED_ATTEMPTS = 5

      attr_reader :store, :identifier

      def initialize(store:, identifier:)
        @store = store
        @identifier = identifier.to_s.strip.downcase
      end

      # Checks if a resend cooldown is currently active.
      # Returns remaining seconds (integer) or nil if cooldown has expired.
      def cooldown_remaining(cooldown_seconds = nil)
        cooldown = cooldown_seconds || default_cooldown_seconds
        last_attempt = latest_attempt
        return nil unless last_attempt

        elapsed = Time.current - last_attempt.created_at
        return nil if elapsed >= cooldown

        (cooldown - elapsed).ceil
      end

      # Checks if hourly OTP dispatch limit has been exceeded.
      def hourly_limit_exceeded?(limit = MAX_HOURLY_DISPATCHES)
        attempts_in_last_hour >= limit
      end

      # Checks if the active attempt has reached max failed verification attempts.
      def locked_out?(max_attempts = MAX_FAILED_ATTEMPTS)
        active_attempt = latest_unverified_attempt
        return false unless active_attempt

        active_attempt.attempts_count >= (active_attempt.max_attempts || max_attempts)
      end

      # Full check for dispatch readiness.
      # Returns [allowed (boolean), reason_code (symbol or nil), retry_after (integer or nil)]
      def check_dispatch_allowed(cooldown_seconds = nil)
        if hourly_limit_exceeded?
          return [false, :hourly_limit_exceeded, 3600]
        end

        remaining = cooldown_remaining(cooldown_seconds)
        if remaining && remaining.positive?
          return [false, :cooldown_active, remaining]
        end

        [true, nil, nil]
      end

      private

      def default_cooldown_seconds
        config = store.respond_to?(:effective_otp_configuration) ? store.effective_otp_configuration : nil
        config&.resend_cooldown_seconds || 30
      end

      def latest_attempt
        Spree::OtpAttempt.where(store: store, identifier: identifier).order(created_at: :desc).first
      end

      def latest_unverified_attempt
        Spree::OtpAttempt.where(store: store, identifier: identifier, verified_at: nil)
                         .where('expires_at > ?', Time.current)
                         .order(created_at: :desc)
                         .first
      end

      def attempts_in_last_hour
        Spree::OtpAttempt.where(store: store, identifier: identifier)
                         .where('created_at > ?', 1.hour.ago)
                         .count
      end
    end
  end
end
