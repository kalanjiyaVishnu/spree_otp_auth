# frozen_string_literal: true

require 'spec_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Storefront Customer Mobile Update & Zero-Lockout Retention API', type: :request do
  include_context 'API v3 Store authenticated'

  let(:user) { create(:user, email: 'customer@example.com') }
  let(:other_user) { create(:user, email: 'other@example.com', mobile_number: '+919876543210') }

  describe 'PATCH /api/v3/store/otp/customer/mobile' do
    context 'when unauthenticated' do
      it 'returns 401 unauthorized when no customer jwt is present' do
        patch '/api/v3/store/otp/customer/mobile',
              params: { mobile_number: '9876543211' }.to_json,
              headers: api_key_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:unauthorized)
        expect(json_response['error']['code']).to eq('authentication_required')
      end
    end

    context 'when authenticated as customer' do
      let(:jwt) { Spree::Api::V3::TestingSupport.generate_jwt(user) }
      let(:auth_headers) do
        api_key_headers.merge(
          'Authorization' => "Bearer #{jwt}",
          'Content-Type' => 'application/json'
        )
      end

      it 'updates customer mobile number with standard E.164 normalization and sets mobile_confirmed_at' do
        patch '/api/v3/store/otp/customer/mobile',
              params: { mobile_number: '9876543219' }.to_json,
              headers: auth_headers

        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.mobile_number).to eq('+919876543219')
        expect(user.mobile_confirmed_at).to be_present
        expect(json_response['user']['mobile_number']).to eq('+919876543219')
        expect(json_response['user']['mobile_confirmed_at']).to be_present
      end

      it 'returns 409 Conflict if mobile is already registered to another user' do
        other_user # ensure created

        patch '/api/v3/store/otp/customer/mobile',
              params: { mobile_number: '9876543210' }.to_json,
              headers: auth_headers

        expect(response).to have_http_status(:conflict)
        expect(json_response['error']['code']).to eq('mobile_already_registered')
      end

      it 'returns 422 if phone format is invalid' do
        patch '/api/v3/store/otp/customer/mobile',
              params: { mobile_number: '123' }.to_json,
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']['code']).to eq('invalid_phone_format')
      end

      it 'returns 422 if mobile_number parameter is missing' do
        patch '/api/v3/store/otp/customer/mobile',
              params: {}.to_json,
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']['code']).to eq('missing_parameter')
      end
    end
  end

  describe 'Zero-Lockout Retention for Legacy Email Accounts' do
    let!(:legacy_user) { create(:user, email: 'legacy@example.com', mobile_number: nil) }

    it 'prompts for mobile when legacy user enters email without phone' do
      post '/api/v3/store/otp/request',
           params: { identifier: 'legacy@example.com' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['requires_mobile']).to be true
    end

    it 'returns 409 Conflict if legacy user provides phone registered to another user' do
      other_user # has '+919876543210'

      post '/api/v3/store/otp/request',
           params: { identifier: 'legacy@example.com', mobile_number: '9876543210' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:conflict)
      expect(json_response['error']['code']).to eq('phone_already_registered')
    end

    it 'dispatches email OTP when legacy user provides unique mobile and links it on verify' do
      post '/api/v3/store/otp/request',
           params: { identifier: 'legacy@example.com', mobile_number: '9876543218' }.to_json,
           headers: api_key_headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['requires_mobile']).to be false

      attempt = Spree::OtpAttempt.last
      expect(attempt.staged_mobile_number).to eq('+919876543218')

      code = '123456'
      attempt.update!(
        code_digest: Spree::OtpAttempt.digest(code, attempt.salt),
        expires_at: 10.minutes.from_now
      )

      expect {
        post '/api/v3/store/otp/verify',
             params: { identifier: 'legacy@example.com', code: code }.to_json,
             headers: api_key_headers.merge('Content-Type' => 'application/json')
      }.not_to change(Spree.user_class, :count)

      expect(response).to have_http_status(:ok)
      legacy_user.reload
      expect(legacy_user.mobile_number).to eq('+919876543218')
      expect(legacy_user.mobile_confirmed_at).to be_present
    end
  end
end
