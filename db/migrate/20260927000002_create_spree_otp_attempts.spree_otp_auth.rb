# frozen_string_literal: true

class CreateSpreeOtpAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_otp_attempts do |t|
      t.references :store, null: false, foreign_key: { to_table: :spree_stores }, index: true
      t.references :user, foreign_key: { to_table: :spree_users }, index: true
      t.string :identifier, null: false
      t.string :channel, null: false
      t.string :code_digest, null: false
      t.string :salt, null: false
      t.integer :attempts_count, null: false, default: 0
      t.integer :max_attempts, null: false, default: 5
      t.datetime :expires_at, null: false
      t.datetime :verified_at
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :spree_otp_attempts, [:identifier, :expires_at]
    add_index :spree_otp_attempts, :verified_at
    add_index :spree_otp_attempts, :created_at
  end
end
