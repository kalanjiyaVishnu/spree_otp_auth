# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Otp::MarketingConsent do
  let(:store) { Spree::Store.default || create(:store) }
  let(:user) { create(:user, email: 'asha@example.com', accepts_email_marketing: false) }

  def call(accept, for_user: user)
    described_class.call(user: for_user, store: store, accept: accept)
  end

  it 'subscribes the customer and records the decision when they opt in' do
    freeze_time do
      call(true)

      expect(user.reload).to have_attributes(accepts_email_marketing: true, email_marketing_decided_at: Time.current)
    end
    subscriber = Spree::NewsletterSubscriber.find_by(email: 'asha@example.com', store: store)
    expect(subscriber).to have_attributes(user_id: user.id)
    expect(subscriber.verified_at).to be_present
    expect(user.marketing_consent_state).to eq(:subscribed)
  end

  it 'records an opt-out and removes an existing subscription' do
    Spree::NewsletterSubscriber.create!(email: 'asha@example.com', store: store, user: user, verified_at: Time.current)
    user.update!(accepts_email_marketing: true)

    call(false)

    expect(user.reload.accepts_email_marketing).to be(false)
    expect(user.email_marketing_decided_at).to be_present
    expect(Spree::NewsletterSubscriber.where(email: 'asha@example.com', store: store)).to be_empty
    expect(user.marketing_consent_state).to eq(:unsubscribed)
  end

  it 'changes nothing when no choice was made' do
    call(nil)

    expect(user.reload.email_marketing_decided_at).to be_nil
    expect(user.marketing_consent_state).to eq(:undecided)
    expect(Spree::NewsletterSubscriber.count).to eq(0)
  end

  it 'never subscribes a synthetic email' do
    synthetic = create(:user, email: '919876543210@guest.ontodi.local')

    call(true, for_user: synthetic)

    expect(Spree::NewsletterSubscriber.count).to eq(0)
    expect(synthetic.reload.email_marketing_decided_at).to be_nil
  end
end
