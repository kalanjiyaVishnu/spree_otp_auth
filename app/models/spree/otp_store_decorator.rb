# frozen_string_literal: true

module Spree
  module OtpStoreDecorator
    def self.prepended(base)
      base.has_one :otp_configuration, class_name: 'Spree::OtpConfiguration', dependent: :destroy
    end

    def effective_otp_configuration
      otp_configuration || Spree::OtpConfiguration.default_for(self)
    end
  end

  Spree::Store.prepend(OtpStoreDecorator) if defined?(Spree::Store)
end
