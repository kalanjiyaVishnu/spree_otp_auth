# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Otp::Verify do
  let(:store) { Spree::Store.default || create(:store) }
  let(:email) { 'shopper@example.com' }
  let(:salt) { Spree::OtpAttempt.generate_salt }
  let(:code) { '123456' }
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

  describe '#call' do
    context 'with valid code' do
      it 'successfully verifies the code and issues JWT and refresh tokens' do
        result = described_class.call(store: store, identifier: email, code: code)

        expect(result).to be_success
        expect(result.value[:user]).to be_present
        expect(result.value[:user].email).to eq(email)
        expect(result.value[:token]).to be_present
        expect(result.value[:refresh_token]).to be_present

        expect(otp_attempt.reload).to be_verified
      end

      it 'locates an existing user without creating a duplicate' do
        existing_user = create(:user, email: email)

        result = described_class.call(store: store, identifier: email, code: code)

        expect(result).to be_success
        expect(result.value[:user].id).to eq(existing_user.id)
      end

      it 'supports mobile phone identifiers and normalizes to E.164' do
        phone_salt = Spree::OtpAttempt.generate_salt
        phone_digest = Spree::OtpAttempt.digest('654321', phone_salt)
        Spree::OtpAttempt.create!(
          store: store,
          identifier: '+919876543210',
          channel: 'mobile',
          code_digest: phone_digest,
          salt: phone_salt,
          expires_at: 10.minutes.from_now
        )

        result = described_class.call(store: store, identifier: '9876543210', code: '654321')

        expect(result).to be_success
        expect(result.value[:user].mobile_number).to eq('+919876543210')
      end

      it 'confirms and saves staged_mobile_number to user record upon email OTP verification' do
        staged_salt = Spree::OtpAttempt.generate_salt
        staged_digest = Spree::OtpAttempt.digest('999888', staged_salt)
        attempt_with_staged_mobile = Spree::OtpAttempt.create!(
          store: store,
          identifier: 'staged.user@example.com',
          channel: 'email',
          staged_mobile_number: '+919876543219',
          code_digest: staged_digest,
          salt: staged_salt,
          expires_at: 10.minutes.from_now
        )

        result = described_class.call(store: store, identifier: 'staged.user@example.com', code: '999888')

        expect(result).to be_success
        user = result.value[:user]
        expect(user.mobile_number).to eq('+919876543219')
        expect(user.mobile_confirmed_at).to be_present
      end
    end

    context 'with invalid code' do
      it 'records a failed attempt and returns failure' do
        result = described_class.call(store: store, identifier: email, code: '000000')

        expect(result).to be_failure
        expect(result.value).to eq(:invalid_otp)
        expect(otp_attempt.reload.attempts_count).to eq(1)
        expect(otp_attempt).not_to be_verified
      end

      it 'locks the attempt when max attempts reached' do
        otp_attempt.update!(attempts_count: 4)

        result = described_class.call(store: store, identifier: email, code: '000000')

        expect(result).to be_failure
        expect(result.value).to eq(:max_attempts_exceeded)
        expect(otp_attempt.reload).to be_locked
      end
    end

    context 'with expired code' do
      it 'rejects verification for an expired attempt' do
        otp_attempt.update!(expires_at: 1.minute.ago)

        result = described_class.call(store: store, identifier: email, code: code)

        expect(result).to be_failure
        expect(result.value).to eq(:invalid_otp)
      end
    end
  end
end
