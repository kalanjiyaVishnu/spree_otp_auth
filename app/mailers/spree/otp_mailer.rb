# frozen_string_literal: true

module Spree
  class OtpMailer < ApplicationMailer
    def send_otp(store:, to:, code:, expiry_minutes: 10)
      @store = store
      @code = code
      @expiry_minutes = expiry_minutes

      smtp_sender = ENV['SMTP_FROM_ADDRESS'].presence ||
                    ActionMailer::Base.smtp_settings[:user_name].presence ||
                    'no-reply@ontodi.com'

      from_address = "#{store.name} <#{smtp_sender}>"
      reply_to_address = store.customer_support_email.presence || store.mail_from_address.presence || smtp_sender

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
