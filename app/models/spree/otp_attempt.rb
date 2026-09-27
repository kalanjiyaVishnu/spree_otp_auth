# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Spree
  class OtpAttempt < Spree::Base
    self.table_name = 'spree_otp_attempts'
    has_prefix_id :otp_att

    belongs_to :store, class_name: 'Spree::Store'
    belongs_to :user, class_name: 'Spree::User', optional: true

    CHANNELS = %w[email mobile whatsapp].freeze

    validates :store, presence: true
    validates :identifier, presence: true
    validates :channel, inclusion: { in: CHANNELS }
    validates :code_digest, presence: true
    validates :salt, presence: true
    validates :expires_at, presence: true
    validates :attempts_count, numericality: { greater_than_or_equal_to: 0 }
    validates :max_attempts, numericality: { greater_than: 0 }
    validates :staged_mobile_number, format: { with: /\A\+[1-9]\d{9,14}\z/, allow_blank: true }

    scope :active, -> { where(verified_at: nil).where('expires_at > ?', Time.current) }
    scope :for_identifier, ->(id) { where(identifier: id) }

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

    def self.generate_salt
      SecureRandom.hex(16)
    end

    def self.digest(code, salt)
      Digest::SHA256.hexdigest("#{salt}#{code.to_s.strip}")
    end
  end
end
