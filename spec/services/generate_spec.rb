# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Otp::Generate do
  let(:store) { create(:store) }
  let!(:config) { gupshup_ready_config(store) }
  let(:mobile) { '9876543210' }
  let(:normalized_mobile) { '+919876543210' }

  def call(**args)
    described_class.call(store: store, identifier: mobile, **args)
  end

  let!(:email_provider_calls) { capture_otp_emails }

  context 'when the number belongs to an account with a real email' do
    let!(:user) { create(:user, email: 'asha@example.com', mobile_number: normalized_mobile) }

    before { stub_gupshup(message_id: 'gs-1') }

    it 'sends the code on WhatsApp and records the Gupshup message id' do
      result = call

      expect(result).to be_success
      expect(result.value).to include(channel: 'whatsapp', requires_email: false, requires_email_code: false,
                                      masked_target: '+91 98*** **210', email_fallback_available: true)
      attempt = Spree::OtpAttempt.last
      expect(attempt).to have_attributes(identifier: normalized_mobile, channel: 'whatsapp', purpose: 'login',
                                         delivery_status: 'submitted', provider_message_id: 'gs-1', user: user)
      expect(attempt.delivery_message_ref).to be_present
      expect(Spree::NotificationDelivery.where(message_ref: attempt.delivery_message_ref).pluck(:provider_key, :outcome))
        .to eq([%w[gupshup delivered]])
      expect(gupshup_send_requests.size).to eq(1)
    end

    it 'does not resend or switch to email when the send may have gone out' do
      stub_gupshup(send_status: :timeout)

      result = call

      expect(result).to be_success
      expect(result.value).to include(channel: 'whatsapp')
      expect(Spree::OtpAttempt.last).to have_attributes(channel: 'whatsapp', delivery_status: 'pending')
      expect(email_provider_calls).to be_empty
    end

    it 'falls back to email when no WhatsApp provider is set up' do
      remove_gupshup(store)

      result = call

      expect(result.value).to include(channel: 'email', auto_fallback: true)
      expect(email_provider_calls.size).to eq(1)
    end

    it 'expires the previous unverified code when a new one is sent' do
      call
      first = Spree::OtpAttempt.last
      travel 31.seconds do
        call

        expect(first.reload).to be_expired
        expect(Spree::OtpAttempt.login.active.where(identifier: normalized_mobile).count).to eq(1)
      end
    end

    it 'keeps the existing cooldown' do
      call
      result = call

      expect(result).to be_failure
      expect(result.value).to eq(:cooldown_active)
    end

    it 'sends to the account email when the admin channel is email' do
      config.update_columns(active_channel: 'email')

      result = call

      expect(result.value).to include(channel: 'email', masked_target: 'a***a@example.com', email_fallback_available: false)
      expect(email_provider_calls.last[:identifier]).to eq('asha@example.com')
      expect(gupshup_send_requests).to be_empty
    end
  end

  context 'when the number is new' do
    before { stub_gupshup }

    it 'asks for an email without creating an attempt' do
      expect { @result = call }.not_to change(Spree::OtpAttempt, :count)

      expect(@result).to be_success
      expect(@result.value).to include(requires_email: true)
    end

    it 'rejects an invalid email' do
      result = call(email: 'not-an-email')

      expect(result.value).to eq(:invalid_email)
    end

    it 'stages an unused email and sends the WhatsApp code' do
      result = call(email: 'New.Person@Example.com')

      expect(result.value).to include(channel: 'whatsapp', requires_email: false)
      expect(Spree::OtpAttempt.last).to have_attributes(staged_email: 'new.person@example.com',
                                                        staged_mobile_number: normalized_mobile, user: nil)
    end

    it 'rejects an email that belongs to an account with a different mobile' do
      create(:user, email: 'taken@example.com', mobile_number: '+919811111111')

      result = call(email: 'taken@example.com')

      expect(result).to be_failure
      expect(result.value).to eq(:email_linked_to_other_mobile)
      expect(gupshup_send_requests).to be_empty
    end

    context 'when the email belongs to an account with no mobile' do
      let!(:email_only) { create(:user, email: 'emailonly@example.com', mobile_number: nil) }

      it 'sends a WhatsApp code and a second code to that email' do
        result = call(email: 'emailonly@example.com')

        expect(result.value).to include(channel: 'whatsapp', requires_email_code: true,
                                        masked_email: 'e***y@example.com', email_fallback_available: false)
        parent = Spree::OtpAttempt.login.last
        child = parent.link_email_attempt
        expect(parent).to have_attributes(user: email_only, staged_mobile_number: normalized_mobile)
        expect(child).to have_attributes(purpose: 'link_email', identifier: 'emailonly@example.com', channel: 'email')
        expect(email_provider_calls.map { |c| c[:identifier] }).to eq(['emailonly@example.com'])
      end

      it 'does not fall back to email when WhatsApp fails' do
        stub_gupshup(send_http_code: 500, send_status: 'error')

        result = call(email: 'emailonly@example.com')

        expect(result.value).to eq(:delivery_failed)
        expect(email_provider_calls).to be_empty
        expect(Spree::OtpAttempt.count).to eq(0)
      end
    end
  end

  context 'when the account only has a synthetic email' do
    before do
      create(:user, email: "919876543210#{Spree::Otp::Identity.synthetic_email_domain}", mobile_number: normalized_mobile)
      stub_gupshup
    end

    it 'treats it as having no email' do
      expect(call.value).to include(requires_email: true)
    end
  end

  context 'when the WhatsApp send fails' do
    let!(:user) { create(:user, email: 'asha@example.com', mobile_number: normalized_mobile) }

    before { stub_gupshup(send_http_code: 500, send_status: 'error') }

    it 'sends the code by email when email backup is on' do
      result = call

      expect(result).to be_success
      expect(result.value).to include(channel: 'email', auto_fallback: true, masked_target: 'a***a@example.com')
      expect(email_provider_calls.size).to eq(1)
      expect(Spree::OtpAttempt.where(identifier: normalized_mobile).pluck(:channel)).to eq(['email'])
    end

    it 'fails and removes the attempt when email backup is off' do
      config.update_columns(fallback_channel: 'none')

      result = call

      expect(result.value).to eq(:delivery_failed)
      expect(Spree::OtpAttempt.count).to eq(0)
      expect(email_provider_calls).to be_empty
    end
  end

  it 'keeps the email-first flow for identifiers with @' do
    create(:user, email: 'legacy@example.com', mobile_number: '+919822222222')

    result = described_class.call(store: store, identifier: 'legacy@example.com')

    expect(result.value).to include(channel: 'email', requires_mobile: false)
    expect(email_provider_calls.last[:identifier]).to eq('legacy@example.com')
  end
end
