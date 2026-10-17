# frozen_string_literal: true

class AddDeliveryFieldsToSpreeOtpAttempts < ActiveRecord::Migration[8.1]
  def change
    change_table :spree_otp_attempts, bulk: true do |t|
      t.string :purpose, null: false, default: 'login' unless column_exists?(:spree_otp_attempts, :purpose)
      t.string :staged_email unless column_exists?(:spree_otp_attempts, :staged_email)
      t.string :provider_message_id unless column_exists?(:spree_otp_attempts, :provider_message_id)
      t.string :delivery_status, null: false, default: 'pending' unless column_exists?(:spree_otp_attempts, :delivery_status)
      t.string :fallback_reason unless column_exists?(:spree_otp_attempts, :fallback_reason)
    end

    unless column_exists?(:spree_otp_attempts, :parent_attempt_id)
      add_reference :spree_otp_attempts, :parent_attempt, foreign_key: { to_table: :spree_otp_attempts }, index: true
    end
    add_index :spree_otp_attempts, :provider_message_id unless index_exists?(:spree_otp_attempts, :provider_message_id)
  end
end
