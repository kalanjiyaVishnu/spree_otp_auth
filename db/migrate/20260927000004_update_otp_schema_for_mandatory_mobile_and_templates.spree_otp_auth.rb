# frozen_string_literal: true

class UpdateOtpSchemaForMandatoryMobileAndTemplates < ActiveRecord::Migration[8.1]
  def change
    # 1. spree_otp_configurations: fallback channel and email template association
    unless column_exists?(:spree_otp_configurations, :fallback_channel)
      add_column :spree_otp_configurations, :fallback_channel, :string, default: 'none', null: false
    end

    unless column_exists?(:spree_otp_configurations, :email_template_id)
      if table_exists?(:spree_email_templates)
        add_reference :spree_otp_configurations, :email_template, foreign_key: { to_table: :spree_email_templates }, index: true
      else
        add_reference :spree_otp_configurations, :email_template, index: true
      end
    end

    # 2. spree_otp_attempts: staged mobile number for progressive disclosure flow
    unless column_exists?(:spree_otp_attempts, :staged_mobile_number)
      add_column :spree_otp_attempts, :staged_mobile_number, :string
    end

    # 3. spree_users: confirmed at timestamp for mobile phone verification
    unless column_exists?(:spree_users, :mobile_confirmed_at)
      add_column :spree_users, :mobile_confirmed_at, :datetime
    end
  end
end
