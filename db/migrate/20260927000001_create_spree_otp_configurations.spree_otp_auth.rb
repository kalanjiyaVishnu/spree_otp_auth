# frozen_string_literal: true

class CreateSpreeOtpConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_otp_configurations do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores }, index: { unique: true }
      t.string :active_channel, null: false, default: 'email'
      t.integer :otp_length, null: false, default: 6
      t.integer :otp_expiry_seconds, null: false, default: 600
      t.integer :resend_cooldown_seconds, null: false, default: 30
      t.integer :fallback_delay_seconds, null: false, default: 20
      t.text :msg91_auth_key
      t.string :msg91_sms_template_id
      t.string :msg91_whatsapp_template_id
      t.string :msg91_sender_id

      t.timestamps
    end
  end
end
