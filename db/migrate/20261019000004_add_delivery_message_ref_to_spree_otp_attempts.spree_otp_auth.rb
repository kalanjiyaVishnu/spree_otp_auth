# frozen_string_literal: true

class AddDeliveryMessageRefToSpreeOtpAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_otp_attempts, :delivery_message_ref, :uuid unless column_exists?(:spree_otp_attempts, :delivery_message_ref)
    add_index :spree_otp_attempts, :delivery_message_ref unless index_exists?(:spree_otp_attempts, :delivery_message_ref)
  end
end
