# frozen_string_literal: true

require 'spec_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Store API v3 OTP Verification', type: :request do
  include_context 'API v3 Store authenticated'

  let(:email) { 'shopper@example.com' }
  let(:code) { '123456' }
  let(:salt) { Spree::OtpAttempt.generate_salt }
  let(:code_digest) { Spree::OtpAttempt.digest(code, salt) }

  let!(:otp_attempt) do
    Spree::OtpAttempt.create!(
      store: store,
      identifier: email,
      channel: 'email',
      code_digest: code_digest,
      salt: salt,
      expires_at: 10.minutes.from_now,
      attempts_count: 0,
      max_attempts: 5
    )
  end

  describe 'POST /api/v3/store/otp/verify' do
    it 'returns 200 with tokens and serialized user upon valid OTP' do
      post '/api/v3/store/otp/verify',
           params: { identifier: email, code: code }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(json_response['token']).to be_present
      expect(json_response['refresh_token']).to be_present
      expect(json_response['user']['email']).to eq(email)
      expect(otp_attempt.reload).to be_verified
    end

    it 'confirms and returns staged mobile number upon successful verification' do
      staged_salt = Spree::OtpAttempt.generate_salt
      staged_digest = Spree::OtpAttempt.digest('654321', staged_salt)
      Spree::OtpAttempt.create!(
        store: store,
        identifier: 'new.staged@example.com',
        channel: 'email',
        staged_mobile_number: '+919876543210',
        code_digest: staged_digest,
        salt: staged_salt,
        expires_at: 10.minutes.from_now
      )

      post '/api/v3/store/otp/verify',
           params: { identifier: 'new.staged@example.com', code: '654321' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(json_response['user']['mobile_number']).to eq('+919876543210')
      user = Spree.user_class.find_by(email: 'new.staged@example.com')
      expect(user.mobile_confirmed_at).to be_present
    end

    it 'returns 401 when code is invalid' do
      post '/api/v3/store/otp/verify',
           params: { identifier: email, code: '000000' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']['code']).to eq('invalid_otp')
      expect(otp_attempt.reload.attempts_count).to eq(1)
    end

    it 'returns 429 when max attempts reached' do
      otp_attempt.update!(attempts_count: 4)

      post '/api/v3/store/otp/verify',
           params: { identifier: email, code: '000000' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:too_many_requests)
      expect(json_response['error']['code']).to eq('max_attempts_exceeded')
      expect(otp_attempt.reload).to be_locked
    end

    it 'returns 422 when required parameters are missing' do
      post '/api/v3/store/otp/verify',
           params: { identifier: email }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['error']['code']).to eq('missing_parameter')
    end
  end
end
