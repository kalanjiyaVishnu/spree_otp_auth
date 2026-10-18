# frozen_string_literal: true

require 'spree/core'
require 'spree_notification_providers'
require 'spree_otp_auth/version'
require 'spree_otp_auth/engine'

module SpreeOtpAuth
  class Error < StandardError; end
  class DeliveryError < Error; end
  class RateLimitError < Error; end
end
