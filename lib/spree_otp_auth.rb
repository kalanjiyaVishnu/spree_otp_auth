# frozen_string_literal: true

require 'spree/core'
require 'spree_notification_providers'
require 'spree_otp_auth/version'
require 'spree_otp_auth/engine'

module SpreeOtpAuth
  # Domain of the placeholder email given to accounts created from a mobile
  # number alone ("<digits>@guest.example.invalid"). Such emails count as
  # "no email". Set it in an initializer to match your storefront:
  #   SpreeOtpAuth.synthetic_email_domain = '@guest.example.local'
  mattr_accessor :synthetic_email_domain, default: '@guest.example.invalid'

  # Optional model (class name) for admin-editable OTP email templates. Its
  # records need `name`, `render_subject(vars)` and `render_body(vars)`, and
  # may be scoped by a `store_id` column. Unset: the built-in mailer view is used.
  #   SpreeOtpAuth.email_template_class = 'Spree::EmailTemplate'
  mattr_accessor :email_template_class, default: nil

  def self.email_template_model
    email_template_class.presence&.safe_constantize
  end

  class Error < StandardError; end
  class DeliveryError < Error; end
  class RateLimitError < Error; end
end
