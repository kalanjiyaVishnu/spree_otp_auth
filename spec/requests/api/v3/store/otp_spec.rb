# frozen_string_literal: true

require 'spec_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Store API v3 OTP Request', type: :request do
  include_context 'API v3 Store authenticated'

  let(:email) { 'shopper@example.com' }
  let!(:existing_user_with_phone) { create(:user, email: email, mobile_number: '+919876543210') }

  describe 'POST /api/v3/store/otp/request' do
    context 'when returning user has a confirmed mobile on file' do
      it 'generates and dispatches OTP immediately' do
        expect do
          post '/api/v3/store/otp/request',
               params: { identifier: email }.to_json,
               headers: api_key_headers.merge('Content-Type' => 'application/json')
        end.to change(Spree::OtpAttempt, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json_response['data']['channel']).to eq('email')
        expect(json_response['data']['masked_target']).to be_present
        expect(json_response['data']['otp_length']).to eq(6)
        expect(json_response['data']['cooldown_seconds']).to eq(30)
        expect(json_response['data']['requires_mobile']).to eq(false)
      end
    end

    context 'when user is new or lacks a mobile phone' do
      let(:new_email) { 'new.shopper@example.com' }

      it 'returns requires_mobile: true when mobile_number is omitted' do
        expect do
          post '/api/v3/store/otp/request',
               params: { identifier: new_email }.to_json,
               headers: api_key_headers.merge('Content-Type' => 'application/json')
        end.not_to change(Spree::OtpAttempt, :count)

        expect(response).to have_http_status(:ok)
        expect(json_response['data']['requires_mobile']).to eq(true)
        expect(json_response['data']['message']).to be_present
      end

      it 'stages mobile and dispatches email OTP when valid mobile_number is provided' do
        expect do
          post '/api/v3/store/otp/request',
               params: { identifier: new_email, mobile_number: '9876543299' }.to_json,
               headers: api_key_headers.merge('Content-Type' => 'application/json')
        end.to change(Spree::OtpAttempt, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json_response['data']['channel']).to eq('email')
        expect(json_response['data']['requires_mobile']).to eq(false)

        attempt = Spree::OtpAttempt.last
        expect(attempt.staged_mobile_number).to eq('+919876543299')
      end

      it 'returns 409 Conflict when mobile_number is already registered to another account' do
        post '/api/v3/store/otp/request',
             params: { identifier: new_email, mobile_number: '+919876543210' }.to_json,
             headers: api_key_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:conflict)
        expect(json_response['error']['code']).to eq('phone_already_registered')
      end
    end

    it 'returns 422 for invalid identifier format' do
      post '/api/v3/store/otp/request',
           params: { identifier: 'not-an-email-or-phone' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['error']['code']).to eq('invalid_identifier')
    end

    it 'returns 429 when cooldown is active' do
      post '/api/v3/store/otp/request',
           params: { identifier: email }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:ok)

      # Immediate second request
      post '/api/v3/store/otp/request',
           params: { identifier: email }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:too_many_requests)
      expect(json_response['error']['code']).to eq('cooldown_active')
      expect(json_response['error']['retry_after_seconds']).to be_positive
    end

    it 'returns 429 when hourly limit of 5 is exceeded' do
      # Create 5 attempts in the last hour
      5.times do |i|
        salt = Spree::OtpAttempt.generate_salt
        Spree::OtpAttempt.create!(
          store: store,
          identifier: email,
          channel: 'email',
          code_digest: Spree::OtpAttempt.digest('123456', salt),
          salt: salt,
          expires_at: 10.minutes.from_now,
          created_at: (50 - i * 5).minutes.ago
        )
      end

      post '/api/v3/store/otp/request',
           params: { identifier: email }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:too_many_requests)
      expect(json_response['error']['code']).to eq('hourly_limit_exceeded')
    end
  end

  describe 'POST /api/v3/store/otp/resend' do
    it 'returns 429 when resending during active cooldown' do
      post '/api/v3/store/otp/request',
           params: { identifier: email }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      post '/api/v3/store/otp/resend',
           params: { identifier: email }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:too_many_requests)
      expect(json_response['error']['code']).to eq('cooldown_active')
    end
  end

  describe 'POST /api/v3/store/otp/whatsapp' do
    it 'dispatches OTP via whatsapp channel for valid phone' do
      post '/api/v3/store/otp/whatsapp',
           params: { identifier: '9876543210' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['channel']).to eq('whatsapp')
    end
  end
end
