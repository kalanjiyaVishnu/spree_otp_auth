# frozen_string_literal: true

module Spree
  module Otp
    # Applies the customer's news-and-offers choice from the login screen (or
    # the account order page) to the user and Spree's newsletter list.
    #
    # accept: true  -> subscribe (verified: they just proved the phone and
    #                  typed or own the email)
    #         false -> record the opt-out and drop any subscription
    #         nil   -> no choice was shown; change nothing
    module MarketingConsent
      module_function

      def call(user:, store:, accept:)
        return if accept.nil? || user.nil?
        return unless Spree::Otp::Identity.real_email?(user.email)

        email = user.email.downcase

        ApplicationRecord.transaction do
          if accept
            Spree::NewsletterSubscriber.subscribe(email: email, user: user, store: store)
            subscriber = Spree::NewsletterSubscriber.find_by(email: email, store: store)
            subscriber&.update!(user: user, verified_at: subscriber.verified_at || Time.current)
          else
            Spree::NewsletterSubscriber.where(email: email, store: store).destroy_all
          end

          user.update_columns(accepts_email_marketing: accept, email_marketing_decided_at: Time.current, updated_at: Time.current)
        end
      end
    end
  end
end
