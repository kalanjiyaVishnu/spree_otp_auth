# frozen_string_literal: true

class AddOtpFieldsToSpreeUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_users, :auth_identifier, :string unless column_exists?(:spree_users, :auth_identifier)
    add_column :spree_users, :auth_channel, :string, default: 'email', null: false unless column_exists?(:spree_users, :auth_channel)
    add_column :spree_users, :mobile_number, :string unless column_exists?(:spree_users, :mobile_number)

    add_index :spree_users, :auth_identifier unless index_exists?(:spree_users, :auth_identifier)
    add_index :spree_users, :mobile_number, unique: true, where: "mobile_number IS NOT NULL AND mobile_number != ''", name: 'idx_spree_users_on_unique_mobile_number' unless index_exists?(:spree_users, :mobile_number, name: 'idx_spree_users_on_unique_mobile_number')
  end
end
