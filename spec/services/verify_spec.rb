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
  describe 'mobile-first logins' do
    let(:mobile) { '+919812345678' }

    def make_attempt(code:, **attrs)
      salt = Spree::OtpAttempt.generate_salt
      Spree::OtpAttempt.create!({
        store: store, identifier: mobile, channel: 'whatsapp', purpose: 'login',
        code_digest: Spree::OtpAttempt.digest(code, salt), salt: salt, expires_at: 10.minutes.from_now
      }.merge(attrs))
    end

    it 'creates the account with the staged email instead of a placeholder' do
      make_attempt(code: '111111', staged_email: 'fresh@example.com', staged_mobile_number: mobile)

      result = described_class.call(store: store, identifier: mobile, code: '111111')

      expect(result).to be_success
      user = result.value[:user]
      expect(user).to have_attributes(email: 'fresh@example.com', mobile_number: mobile)
      expect(user.mobile_confirmed_at).to be_present
    end

    it 'replaces a synthetic email on an existing mobile account' do
      user = create(:user, email: "919812345678#{Spree::Otp::Identity.synthetic_email_domain}", mobile_number: mobile)
      make_attempt(code: '111111', user: user, staged_email: 'real@example.com')

      described_class.call(store: store, identifier: mobile, code: '111111')

      expect(user.reload.email).to eq('real@example.com')
    end

    it 'rejects a code that was superseded by a newer one' do
      make_attempt(code: '111111').expire!
      make_attempt(code: '222222')

      expect(described_class.call(store: store, identifier: mobile, code: '111111').value).to eq(:invalid_otp)
      expect(described_class.call(store: store, identifier: mobile, code: '222222')).to be_success
    end

    it 'does not confirm the phone when the login finished with an email backup code' do
      user = create(:user, email: 'asha@example.com', mobile_number: mobile, mobile_confirmed_at: nil)
      make_attempt(code: '111111', user: user, channel: 'email')

      described_class.call(store: store, identifier: mobile, code: '111111')

      expect(user.reload.mobile_confirmed_at).to be_nil
    end

    context 'when linking the number to an email-only account' do
      let!(:email_only) { create(:user, email: 'emailonly@example.com', mobile_number: nil) }
      let!(:parent) { make_attempt(code: '111111', user: email_only, staged_mobile_number: mobile) }
      let!(:child) do
        salt = Spree::OtpAttempt.generate_salt
        Spree::OtpAttempt.create!(
          store: store, identifier: 'emailonly@example.com', channel: 'email', purpose: 'link_email',
          parent_attempt: parent, user: email_only, code_digest: Spree::OtpAttempt.digest('999999', salt),
          salt: salt, expires_at: parent.expires_at
        )
      end

      it 'needs both codes and then attaches the number to that account' do
        result = described_class.call(store: store, identifier: mobile, code: '111111', email_code: '999999')

        expect(result).to be_success
        expect(result.value[:user].id).to eq(email_only.id)
        expect(email_only.reload).to have_attributes(mobile_number: mobile)
        expect(email_only.mobile_confirmed_at).to be_present
        expect(child.reload).to be_verified
      end

      it 'fails without the email code and only counts against the email code' do
        result = described_class.call(store: store, identifier: mobile, code: '111111', email_code: '000000')

        expect(result.value).to eq(:invalid_email_code)
        expect(child.reload.attempts_count).to eq(1)
        expect(parent.reload).to have_attributes(attempts_count: 0, verified_at: nil)
        expect(email_only.reload.mobile_number).to be_nil
      end

      it 'fails on a wrong WhatsApp code and only counts against it' do
        result = described_class.call(store: store, identifier: mobile, code: '000000', email_code: '999999')

        expect(result.value).to eq(:invalid_otp)
        expect(parent.reload.attempts_count).to eq(1)
        expect(child.reload.attempts_count).to eq(0)
      end
    end
  end
end
