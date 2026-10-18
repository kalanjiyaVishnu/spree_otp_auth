# frozen_string_literal: true

module Spree
  class OtpConfiguration < Spree::Base
    self.table_name = 'spree_otp_configurations'
    has_prefix_id :otp_cfg

    belongs_to :store, class_name: 'Spree::Store'

    CHANNELS = %w[email mobile whatsapp].freeze
    FALLBACK_CHANNELS = %w[none whatsapp sms email].freeze

    alias_attribute :auth_channel, :active_channel

    # Legacy provider columns (msg91_*, gupshup_*) are read only by the
    # one-time import into spree_notification_providers and are dropped in a
    # later release. Providers, credentials and templates now live in
    # Admin -> Settings -> Notification providers.
    encrypts :msg91_auth_key, deterministic: false

    validates :store_id, uniqueness: true, presence: true
    validates :active_channel, inclusion: { in: CHANNELS }
    validates :fallback_channel, inclusion: { in: FALLBACK_CHANNELS }
    validates :otp_length, inclusion: { in: [4, 6] }
    validates :otp_expiry_seconds, numericality: { greater_than_or_equal_to: 60 }
    validates :resend_cooldown_seconds, numericality: { greater_than_or_equal_to: 10 }
    validates :fallback_delay_seconds, numericality: { greater_than_or_equal_to: 10 }
    validate :active_channel_ready, if: -> { %w[whatsapp mobile].include?(active_channel) }

    # What still stops the store sending login codes on `channel`, as labels.
    def missing_requirements(channel = active_channel)
      return [] if channel.to_s == 'email'

      provider_channel = Spree::Otp::Delivery.provider_channel(channel)
      statuses = SpreeNotificationProviders.channel_status(store, provider_channel)
      return ["#{channel.to_s == 'mobile' ? 'an' : 'a'} #{channel_name(channel)} provider"] if statuses.empty?
      return [] if Spree::Otp::Delivery.ready?(store, channel)

      enabled = statuses.reject { |s| s[:status] == :disabled }
      return ["an enabled #{channel_name(channel)} provider"] if enabled.empty?

      missing = enabled.flat_map { |s| s[:missing] }.uniq
      missing.presence || ['a "Login code" template']
    end

    def channel_ready?(channel = active_channel)
      missing_requirements(channel).empty?
    end

    # The admin-chosen email template, when the app provides a template model
    # (SpreeOtpAuth.email_template_class).
    def email_template
      model = SpreeOtpAuth.email_template_model
      model && email_template_id.present? ? model.find_by(id: email_template_id) : nil
    end

    def email_template=(template)
      self.email_template_id = template&.id
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
      end
    end

    private

    def active_channel_ready
      missing = missing_requirements
      return if missing.empty?

      errors.add(:active_channel, "can't be #{channel_name(active_channel)} yet. Missing: #{missing.join(', ')}. " \
                                  'Set this up in Settings → Notification providers.')
    end

    def channel_name(channel)
      channel.to_s == 'mobile' ? 'SMS' : channel.to_s.titleize.sub('Whatsapp', 'WhatsApp')
    end
  end
end
