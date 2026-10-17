# frozen_string_literal: true

class AddEmailMarketingDecidedAtToSpreeUsers < ActiveRecord::Migration[8.1]
  # Null = the customer never made a news-and-offers choice; with
  # accepts_email_marketing = false and a timestamp, they opted out.
  def up
    add_column :spree_users, :email_marketing_decided_at, :datetime unless column_exists?(:spree_users, :email_marketing_decided_at)

    # Customers already on a verified newsletter subscription count as
    # subscribed, decided when they first subscribed.
    execute <<~SQL.squish
      UPDATE spree_users u
      SET accepts_email_marketing = TRUE,
          email_marketing_decided_at = s.first_subscribed_at
      FROM (
        SELECT COALESCE(ns.user_id, matched.id) AS user_id, MIN(ns.created_at) AS first_subscribed_at
        FROM spree_newsletter_subscribers ns
        LEFT JOIN spree_users matched
          ON ns.user_id IS NULL AND LOWER(matched.email) = LOWER(ns.email)
        WHERE ns.verified_at IS NOT NULL
        GROUP BY COALESCE(ns.user_id, matched.id)
      ) s
      WHERE s.user_id IS NOT NULL AND u.id = s.user_id
    SQL
  end

  def down
    remove_column :spree_users, :email_marketing_decided_at if column_exists?(:spree_users, :email_marketing_decided_at)
  end
end
