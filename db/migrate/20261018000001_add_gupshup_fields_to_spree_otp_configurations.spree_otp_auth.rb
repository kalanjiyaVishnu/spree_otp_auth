# frozen_string_literal: true

class AddGupshupFieldsToSpreeOtpConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_otp_configurations, :gupshup_source_number, :string unless column_exists?(:spree_otp_configurations, :gupshup_source_number)
    add_column :spree_otp_configurations, :gupshup_app_name, :string unless column_exists?(:spree_otp_configurations, :gupshup_app_name)
    add_column :spree_otp_configurations, :gupshup_app_id, :string unless column_exists?(:spree_otp_configurations, :gupshup_app_id)
    unless column_exists?(:spree_otp_configurations, :gupshup_template_name)
      add_column :spree_otp_configurations, :gupshup_template_name, :string, default: 'verify_otp'
    end
    add_column :spree_otp_configurations, :gupshup_template_id, :string unless column_exists?(:spree_otp_configurations, :gupshup_template_id)

    # New stores default to WhatsApp with email backup. Existing rows keep their
    # channel until an admin switches after a successful test send.
    change_column_default :spree_otp_configurations, :active_channel, from: 'email', to: 'whatsapp'
    change_column_default :spree_otp_configurations, :fallback_channel, from: 'none', to: 'email'
  end
end
