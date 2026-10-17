# frozen_string_literal: true

module Spree
  class OtpConfiguration < Spree::Base
    self.table_name = 'spree_otp_configurations'
    has_prefix_id :otp_cfg

    belongs_to :store, class_name: 'Spree::Store'
    belongs_to :email_template, class_name: 'Spree::EmailTemplate', optional: true

    CHANNELS = %w[email mobile whatsapp].freeze
    FALLBACK_CHANNELS = %w[none whatsapp sms email].freeze
    DEFAULT_GUPSHUP_TEMPLATE_NAME = 'verify_otp'
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    alias_attribute :auth_channel, :active_channel

    encrypts :msg91_auth_key, deterministic: false

    validates :store_id, uniqueness: true, presence: true
    validates :active_channel, inclusion: { in: CHANNELS }
    validates :fallback_channel, inclusion: { in: FALLBACK_CHANNELS }
    validates :otp_length, inclusion: { in: [4, 6] }
    validates :otp_expiry_seconds, numericality: { greater_than_or_equal_to: 60 }
    validates :resend_cooldown_seconds, numericality: { greater_than_or_equal_to: 10 }
    validates :fallback_delay_seconds, numericality: { greater_than_or_equal_to: 10 }
    validates :gupshup_source_number, format: { with: /\A[1-9]\d{9,14}\z/ }, allow_blank: true
    validates :gupshup_template_id, format: { with: UUID_FORMAT }, allow_blank: true
    validate :whatsapp_requirements_met, if: -> { active_channel == 'whatsapp' }

    before_validation :normalize_gupshup_fields

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

    # The Gupshup API key lives only in the server environment (GUPSHUP_API_KEY).
    def gupshup_api_key_present?
      Spree::Otp::Provider::GupshupWhatsapp.api_key.present?
    end

    def effective_gupshup_template_name
      gupshup_template_name.presence || DEFAULT_GUPSHUP_TEMPLATE_NAME
    end

    def missing_whatsapp_requirements
      missing = []
      missing << 'API key (GUPSHUP_API_KEY in the server environment)' unless gupshup_api_key_present?
      missing << 'source number' if gupshup_source_number.blank?
      missing << 'app name' if gupshup_app_name.blank?
      missing << 'app ID (or a template ID)' if gupshup_template_id.blank? && gupshup_app_id.blank?
      missing
    end

    def whatsapp_ready?
      missing_whatsapp_requirements.empty?
    end

    def email_fallback_enabled?
      fallback_channel == 'email'
    end

    def self.default_for(store)
      find_or_initialize_by(store: store) do |cfg|
        cfg.active_channel = 'whatsapp'
        cfg.fallback_channel = 'email'
        cfg.otp_length = 6
        cfg.otp_expiry_seconds = 600
        cfg.resend_cooldown_seconds = 30
        cfg.fallback_delay_seconds = 20
        cfg.gupshup_template_name = DEFAULT_GUPSHUP_TEMPLATE_NAME
      end
    end

    private

    def normalize_gupshup_fields
      self.gupshup_source_number = gupshup_source_number.to_s.gsub(/\D/, '').presence if gupshup_source_number
      %i[gupshup_app_name gupshup_app_id gupshup_template_name gupshup_template_id].each do |attr|
        self[attr] = self[attr].to_s.strip.presence if self[attr]
      end
    end

    def whatsapp_requirements_met
      missing = missing_whatsapp_requirements
      return if missing.empty?

      errors.add(:active_channel, "can't be WhatsApp yet. Missing: #{missing.join(', ')}")
    end
  end
end
