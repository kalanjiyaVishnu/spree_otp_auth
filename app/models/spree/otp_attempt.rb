# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Spree
  class OtpAttempt < Spree::Base
    self.table_name = 'spree_otp_attempts'
    has_prefix_id :otp_att

    belongs_to :store, class_name: 'Spree::Store'
    belongs_to :user, class_name: 'Spree::User', optional: true
    belongs_to :parent_attempt, class_name: 'Spree::OtpAttempt', optional: true
    has_one :link_email_attempt, class_name: 'Spree::OtpAttempt', foreign_key: :parent_attempt_id,
                                 inverse_of: :parent_attempt, dependent: :destroy

    CHANNELS = %w[email mobile whatsapp].freeze
    PURPOSES = %w[login link_email].freeze
    DELIVERY_STATUSES = %w[pending submitted failed fallback_sent].freeze

    validates :store, presence: true
    validates :identifier, presence: true
    validates :channel, inclusion: { in: CHANNELS }
    validates :purpose, inclusion: { in: PURPOSES }
    validates :delivery_status, inclusion: { in: DELIVERY_STATUSES }
    validates :code_digest, presence: true
    validates :salt, presence: true
    validates :expires_at, presence: true
    validates :attempts_count, numericality: { greater_than_or_equal_to: 0 }
    validates :max_attempts, numericality: { greater_than: 0 }
    validates :staged_mobile_number, format: { with: /\A\+[1-9]\d{9,14}\z/, allow_blank: true }
    validates :staged_email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

    scope :active, -> { where(verified_at: nil).where('expires_at > ?', Time.current) }
    scope :for_identifier, ->(id) { where(identifier: id) }
    scope :login, -> { where(purpose: 'login') }

    def expired?
      Time.current >= expires_at
    end

    def verified?
      verified_at.present?
    end

    def locked?
      attempts_count >= max_attempts
    end

    def valid_code?(submitted_code)
      return false if expired? || verified? || locked?
      return false if submitted_code.blank?

      candidate_digest = self.class.digest(submitted_code, salt)
      ActiveSupport::SecurityUtils.secure_compare(code_digest, candidate_digest)
    end

    def record_failed_attempt!
      increment!(:attempts_count)
    end

    def mark_verified!
      update!(verified_at: Time.current)
    end

    # Invalidates this code (and its link_email child) without deleting the
    # record, so the hourly limiter and admin diagnostics still see it.
    def expire!
      now = Time.current
      update_columns(expires_at: now, updated_at: now)
      link_email_attempt&.update_columns(expires_at: now, updated_at: now)
    end

    def self.generate_salt
      SecureRandom.hex(16)
    end

    def self.digest(code, salt)
      Digest::SHA256.hexdigest("#{salt}#{code.to_s.strip}")
    end
  end
end
