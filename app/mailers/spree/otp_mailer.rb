# frozen_string_literal: true

module Spree
  class OtpMailer < ApplicationMailer
    def send_otp(store:, to:, code:, expiry_minutes: 10)
      @store = store
      @code = code
      @expiry_minutes = expiry_minutes

      # Routed through the store's email providers (spree_notification_providers).
      # The sender is left to the provider: SMTP uses its own from address, so
      # the code never goes out from an address the SMTP account can't send as.
      headers['X-Spree-Store-Id'] = store.id.to_s
      headers['X-Spree-Message-Type'] = 'otp_code'

      from_address = nil
      reply_to_address = store.customer_support_email.presence || store.mail_from_address.presence

      config = store.otp_configuration || (store.respond_to?(:effective_otp_configuration) ? store.effective_otp_configuration : nil)
      template = config&.email_template

      if template
        begin
          variables = {
            'otp_code' => code.to_s,
            'store_name' => store.name.to_s,
            'expiry_minutes' => expiry_minutes.to_s,
            'OTP_CODE' => code.to_s,
            'STORE_NAME' => store.name.to_s,
            'EXPIRY_MINUTES' => expiry_minutes.to_s
          }
          rendered_subject = template.render_subject(variables)
          rendered_body = template.render_body(variables)

          return mail(
            to: to,
            from: from_address,
            reply_to: reply_to_address,
            subject: rendered_subject.presence || "#{code} is your #{store.name} verification code"
          ) do |format|
            format.html { render html: rendered_body.html_safe }
            format.text { render plain: ActionView::Base.full_sanitizer.sanitize(rendered_body) }
          end
        rescue StandardError => e
          Rails.logger.warn("[SpreeOtpAuth] Failed to render email template #{template.id}: #{e.message}. Falling back to default mailer.")
        end
      end

      mail(
        to: to,
        from: from_address,
        reply_to: reply_to_address,
        subject: "#{code} is your #{store.name} verification code"
      )
    end
  end
end
