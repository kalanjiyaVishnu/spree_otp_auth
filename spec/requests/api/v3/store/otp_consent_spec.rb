# frozen_string_literal: true

require 'spec_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Store API v3 OTP marketing consent', type: :request do
  include_context 'API v3 Store authenticated'

  let(:mobile) { '9876543210' }
  let(:headers) { api_key_headers.merge('Content-Type' => 'application/json') }

  before do
    gupshup_ready_config(store)
    stub_gupshup
    allow(Spree::Otp::Generate).to receive(:generate_code).and_return('123456')
  end

  def request_code(**extra)
    post '/api/v3/store/otp/request', params: { identifier: mobile, **extra }.to_json, headers: headers
    json_response['data']
  end

  def verify(**extra)
    post '/api/v3/store/otp/verify', params: { identifier: mobile, code: '123456', **extra }.to_json, headers: headers
  end

  context 'with a new number' do
    it 'asks for the email with the consent box ticked by default' do
      expect(request_code).to include('requires_email' => true, 'show_marketing_consent' => true,
                                      'marketing_consent_default' => true)
    end

    it 'subscribes the new customer when they keep the box ticked' do
      request_code(email: 'new@example.com')
      verify(accept_marketing: true)

      expect(response).to have_http_status(:ok)
      expect(json_response['user']['accepts_email_marketing']).to be(true)
      expect(Spree::NewsletterSubscriber.where(email: 'new@example.com', store: store)).to exist
    end

    it 'does not subscribe when they untick the box' do
      request_code(email: 'new@example.com')
      verify(accept_marketing: false)

      user = Spree.user_class.find_by(email: 'new@example.com')
      expect(user.accepts_email_marketing).to be(false)
      expect(user.email_marketing_decided_at).to be_present
      expect(Spree::NewsletterSubscriber.count).to eq(0)
    end
  end

  context 'with a returning customer' do
    let!(:user) { create(:user, email: 'asha@example.com', mobile_number: '+919876543210', accepts_email_marketing: false) }

    it 'shows a ticked box when they never decided' do
      expect(request_code).to include('show_marketing_consent' => true, 'marketing_consent_default' => true)
    end

    it 'shows an unticked box when they unsubscribed before' do
      user.update!(email_marketing_decided_at: 1.month.ago)

      expect(request_code).to include('show_marketing_consent' => true, 'marketing_consent_default' => false)
    end

    it 'hides the box when they are already subscribed' do
      user.update!(accepts_email_marketing: true, email_marketing_decided_at: 1.month.ago)

      expect(request_code).to include('show_marketing_consent' => false)
    end

    it 'leaves consent untouched when verify carries no choice' do
      request_code
      verify

      expect(user.reload.email_marketing_decided_at).to be_nil
      expect(Spree::NewsletterSubscriber.count).to eq(0)
    end

    it 're-subscribes a past unsubscriber only when they tick the box' do
      user.update!(email_marketing_decided_at: 1.month.ago)
      request_code
      verify(accept_marketing: true)

      expect(user.reload.accepts_email_marketing).to be(true)
    end
  end
end
