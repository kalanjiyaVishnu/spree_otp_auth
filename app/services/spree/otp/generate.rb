# frozen_string_literal: true

require 'securerandom'

module Spree
  module Otp
    # Starts a login: finds the account, decides what still has to be collected,
    # and sends the code.
    #
    # Mobile-first (identifier is a phone number, the default storefront flow):
    #   * account with a real email      -> code sent on the active channel
    #   * new number / no real email     -> requires_email until an email is given
    #   * email owned by another mobile  -> :email_linked_to_other_mobile
    #   * email owned by an account with no mobile -> code on WhatsApp plus a
    #     second code to that email (link_email child attempt); both are needed
    #
    # Email-first (identifier contains "@") keeps the feature-010 behaviour.
    class Generate
      prepend Spree::ServiceModule::Base

      def self.generate_code(length)
        min = 10**(length - 1)
        max = (10**length) - 1
        SecureRandom.random_number(min..max).to_s
      end

      def call(store:, identifier:, mobile_number: nil, email: nil, channel: nil, request_env: {})
        normalized_identifier, kind = Spree::Otp::Identity.normalize_identifier(identifier)
        return failure(:invalid_identifier, 'Invalid email or phone number format.') if normalized_identifier.blank?

        config = store.effective_otp_configuration
        context = kind == 'email' ? email_first(normalized_identifier, mobile_number) : mobile_first(normalized_identifier, email)
        return context if context.is_a?(Spree::ServiceModule::Result)

        rate_limiter = Spree::Otp::RateLimiter.new(store: store, identifier: normalized_identifier)
        allowed, reason, retry_after = rate_limiter.check_dispatch_allowed(config.resend_cooldown_seconds)
        unless allowed
          if reason == :hourly_limit_exceeded
            return failure(:hourly_limit_exceeded, 'Hourly limit of 5 codes exceeded. Please try again later.')
          end

          return failure(:cooldown_active, { message: "Please wait #{retry_after} seconds before requesting another code.", retry_after_seconds: retry_after })
        end

        active_channel = channel.presence || (kind == 'email' ? 'email' : config.active_channel)
        expire_previous_attempts(store, normalized_identifier)

        code = self.class.generate_code(config.otp_length || 6)
        attempt = create_attempt(store, config, normalized_identifier, active_channel, code, context, request_env)

        destination = Spree::Otp::Delivery.destination_for(attempt)
        if destination.blank?
          attempt.destroy
          return failure(:no_email_on_account, 'There is no email on this account to send a code to.')
        end

        dispatch_result = Spree::Otp::Delivery.provider_for(active_channel, store).send_otp(
          identifier: destination,
          code: code,
          metadata: { expiry_minutes: ((config.otp_expiry_seconds || 600) / 60) }
        )

        auto_fallback = false
        if dispatch_result.failure?
          attempt.update_columns(delivery_status: 'failed', fallback_reason: dispatch_result.error_message.to_s.truncate(120))

          fallback = try_email_fallback(store, config, attempt, dispatch_result.error_message, linking: context[:link_user].present?)
          if fallback&.success?
            attempt = fallback.value[:attempt]
            auto_fallback = true
          else
            attempt.destroy # Clean up unsent attempt so cooldown isn't unfairly triggered
            return failure(:delivery_failed, dispatch_result.error_message || 'Failed to deliver passcode.')
          end
        else
          attempt.update_columns(delivery_status: 'submitted', provider_message_id: dispatch_result.message_id)
        end

        if context[:link_user]
          link_result = send_link_email_code(store, config, attempt, context[:link_user], request_env)
          return link_result if link_result
        end

        success(Spree::Otp::CodeSentPayload.build(attempt: attempt.reload, config: config, auto_fallback: auto_fallback))
      end

      private

      # Returns a context hash, or a Result to return straight away.
      def mobile_first(mobile, email)
        user = Spree.user_class.find_by(mobile_number: mobile)
        return { user: user } if user && Spree::Otp::Identity.real_email?(user.email)

        normalized_email = Spree::Otp::Identity.normalize_email(email)
        if normalized_email.blank?
          return success(Spree::Otp::CodeSentPayload.requires_email(user))
        end
        return failure(:invalid_email, 'Please enter a valid email address.') unless Spree::Otp::Identity.valid_email?(normalized_email)

        email_owner = Spree.user_class.find_by('LOWER(email) = ?', normalized_email)
        if email_owner && email_owner != user
          if email_owner.mobile_number.present? || user.present?
            return failure(:email_linked_to_other_mobile,
                           'This email is already linked to another mobile number. Please sign in with the mobile number linked to that email.')
          end

          # Email-only account: the customer must also prove they own the email.
          return { user: email_owner, staged_mobile: mobile, link_user: email_owner }
        end

        { user: user, staged_email: normalized_email, staged_mobile: user ? nil : mobile }
      end

      def email_first(email, mobile_number)
        user = Spree.user_class.find_by('LOWER(email) = ?', email)
        return { user: user } if user&.mobile_number.present?

        if mobile_number.blank?
          return success(requires_mobile: true, message: 'Mobile number is required to continue.')
        end

        normalized_mobile = Spree::Otp::Identity.normalize_phone(mobile_number)
        return failure(:invalid_phone, 'Invalid mobile phone number format.') unless Spree::Otp::Identity.valid_phone?(normalized_mobile)

        existing_mobile_user = Spree.user_class.find_by(mobile_number: normalized_mobile)
        if existing_mobile_user && existing_mobile_user.id != user&.id
          return failure(:phone_already_registered, 'This mobile number is already linked to another account.')
        end

        { user: user, staged_mobile: normalized_mobile }
      end

      # Only the newest login code for an identifier is valid.
      def expire_previous_attempts(store, identifier)
        Spree::OtpAttempt.where(store: store, identifier: identifier).login.active.find_each(&:expire!)
      end

      def create_attempt(store, config, identifier, channel, code, context, request_env)
        salt = Spree::OtpAttempt.generate_salt
        Spree::OtpAttempt.create!(
          store: store,
          user: context[:user],
          identifier: identifier,
          channel: channel,
          purpose: 'login',
          code_digest: Spree::OtpAttempt.digest(code, salt),
          salt: salt,
          staged_mobile_number: context[:staged_mobile],
          staged_email: context[:staged_email],
          expires_at: (config.otp_expiry_seconds || 600).seconds.from_now,
          ip_address: request_env[:ip_address],
          user_agent: request_env[:user_agent]&.truncate(255)
        )
      end

      # Linking a number to an email-only account needs proof of the phone, so
      # the email backup can't stand in for the WhatsApp code there.
      def try_email_fallback(store, config, attempt, reason, linking:)
        return nil if linking || attempt.channel == 'email' || !config.email_fallback_enabled?

        Spree::Otp::Fallback.call(store: store, attempt: attempt, reason: reason, enforce_cooldown: false, discard_original: true)
      end

      # Second code for the "link this number to an email-only account" case.
      # Returns a failure Result when it can't be sent, else nil.
      def send_link_email_code(store, config, attempt, link_user, request_env)
        code = self.class.generate_code(config.otp_length || 6)
        salt = Spree::OtpAttempt.generate_salt
        child = Spree::OtpAttempt.create!(
          store: store,
          user: link_user,
          parent_attempt: attempt,
          identifier: link_user.email.downcase,
          channel: 'email',
          purpose: 'link_email',
          code_digest: Spree::OtpAttempt.digest(code, salt),
          salt: salt,
          expires_at: attempt.expires_at,
          ip_address: request_env[:ip_address],
          user_agent: request_env[:user_agent]&.truncate(255)
        )

        result = Spree::Otp::Provider::Email.new(store).send_otp(
          identifier: child.identifier,
          code: code,
          metadata: { expiry_minutes: ((config.otp_expiry_seconds || 600) / 60) }
        )
        if result.failure?
          attempt.destroy
          return failure(:delivery_failed, 'Failed to send the code to your email.')
        end

        child.update_columns(delivery_status: 'submitted', provider_message_id: result.message_id)
        nil
      end
    end
  end
end
