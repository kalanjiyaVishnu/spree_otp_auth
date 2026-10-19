# frozen_string_literal: true

require 'spec_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Store API v3 OTP mobile-first flow', type: :request do
  include_context 'API v3 Store authenticated'

  let(:mobile) { '9876543210' }
  let(:headers) { api_key_headers.merge('Content-Type' => 'application/json') }
  let!(:config) { gupshup_ready_config(store) }

  before do
    stub_gupshup
    capture_otp_emails
  end

  describe 'POST /api/v3/store/otp/request' do
    it 'asks for an email for a new number' do
      post '/api/v3/store/otp/request', params: { identifier: mobile }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['requires_email']).to eq(true)
    end

    it 'sends a WhatsApp code once the email is given' do
      post '/api/v3/store/otp/request', params: { identifier: mobile, email: 'new@example.com' }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to include('channel' => 'whatsapp', 'requires_email' => false,
                                               'email_fallback_available' => true)
    end

    it 'returns 409 when the email is linked to another mobile' do
      create(:user, email: 'taken@example.com', mobile_number: '+919811111111')

      post '/api/v3/store/otp/request', params: { identifier: mobile, email: 'taken@example.com' }.to_json, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(json_response['error']['code']).to eq('email_linked_to_other_mobile')
    end
  end

  context 'with a code already sent on WhatsApp' do
    let!(:user) { create(:user, email: 'asha@example.com', mobile_number: '+919876543210') }

    before { post '/api/v3/store/otp/request', params: { identifier: mobile }.to_json, headers: headers }

    describe 'POST /api/v3/store/otp/fallback' do
      it 'returns 429 during the resend cooldown' do
        post '/api/v3/store/otp/fallback', params: { identifier: mobile }.to_json, headers: headers

        expect(response).to have_http_status(:too_many_requests)
        expect(json_response['error']['code']).to eq('cooldown_active')
      end

      it 'sends the code by email after the cooldown and invalidates the WhatsApp code' do
        whatsapp_attempt = Spree::OtpAttempt.last

        travel 31.seconds do
          post '/api/v3/store/otp/fallback', params: { identifier: mobile }.to_json, headers: headers

          expect(response).to have_http_status(:ok)
          expect(json_response['data']).to include('channel' => 'email', 'masked_target' => 'a***a@example.com')
          expect(whatsapp_attempt.reload).to have_attributes(delivery_status: 'fallback_sent')
          expect(whatsapp_attempt).to be_expired
        end
      end

      it 'returns 404 when email backup is off' do
        config.update_columns(fallback_channel: 'none')

        travel 31.seconds do
          post '/api/v3/store/otp/fallback', params: { identifier: mobile }.to_json, headers: headers
        end

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']['code']).to eq('email_fallback_disabled')
      end
    end

    describe 'POST /api/v3/store/otp/status' do
      it 'reports the WhatsApp code as submitted' do
        post '/api/v3/store/otp/status', params: { identifier: mobile }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json_response['data']).to include('channel' => 'whatsapp', 'delivery_status' => 'submitted',
                                                 'masked_target' => '+91 98*** **210')
      end

      it 'reports fallback_sent after an automatic switch to email' do
        Spree::Otp::Fallback.call(store: store, attempt: Spree::OtpAttempt.last, reason: 'failed', enforce_cooldown: false)

        post '/api/v3/store/otp/status', params: { identifier: mobile }.to_json, headers: headers

        expect(json_response['data']).to include('channel' => 'email', 'delivery_status' => 'fallback_sent',
                                                 'masked_target' => 'a***a@example.com')
      end
    end
  end

  it 'returns 422 from fallback when the account has no email' do
    create(:user, email: "919876543210#{Spree::Otp::Identity.synthetic_email_domain}", mobile_number: '+919876543210')
    salt = Spree::OtpAttempt.generate_salt
    Spree::OtpAttempt.create!(store: store, identifier: '+919876543210', channel: 'whatsapp',
                              code_digest: Spree::OtpAttempt.digest('111111', salt), salt: salt,
                              expires_at: 10.minutes.from_now, created_at: 1.minute.ago)

    post '/api/v3/store/otp/fallback', params: { identifier: mobile }.to_json, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response['error']['code']).to eq('no_email_on_account')
  end
end
