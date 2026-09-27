# frozen_string_literal: true

module Spree
  class OtpConfiguration < Spree::Base
    self.table_name = 'spree_otp_configurations'
    has_prefix_id :otp_cfg

    belongs_to :store, class_name: 'Spree::Store'
    belongs_to :email_template, class_name: 'Spree::EmailTemplate', optional: true

    CHANNELS = %w[email mobile whatsapp].freeze
    FALLBACK_CHANNELS = %w[none whatsapp sms email].freeze

    alias_attribute :auth_channel, :active_channel

    encrypts :msg91_auth_key, deterministic: false

    validates :store_id, uniqueness: true, presence: true
    validates :active_channel, inclusion: { in: CHANNELS }
    validates :fallback_channel, inclusion: { in: FALLBACK_CHANNELS }
    validates :otp_length, inclusion: { in: [4, 6] }
    validates :otp_expiry_seconds, numericality: { greater_than_or_equal_to: 60 }
    validates :resend_cooldown_seconds, numericality: { greater_than_or_equal_to: 10 }
    validates :fallback_delay_seconds, numericality: { greater_than_or_equal_to: 10 }

    def effective_msg91_auth_key
      msg91_auth_key.presence || ENV.fetch('MSG91_AUTH_KEY', nil)
    end

    def effective_msg91_sms_template_id
      msg91_sms_template_id.presence || ENV.fetch('MSG91_SMS_OTP_TEMPLATE_ID', nil)
    end

    def effective_msg91_whatsapp_template_id
      msg91_whatsapp_template_id.presence || ENV.fetch('MSG91_WHATSAPP_OTP_TEMPLATE_ID', nil)
    end

    def effective_msg91_sender_id
      msg91_sender_id.presence || ENV.fetch('MSG91_SENDER_ID', 'ONTODI')
    end

    def self.default_for(store)
      find_or_initialize_by(store: store) do |cfg|
        cfg.active_channel = 'email'
        cfg.fallback_channel = 'none'
        cfg.otp_length = 6
        cfg.otp_expiry_seconds = 600
        cfg.resend_cooldown_seconds = 30
        cfg.fallback_delay_seconds = 20
      end
    end
  end
end
