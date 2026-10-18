# frozen_string_literal: true

require 'spec_helper'

# A WhatsApp code Gupshup reports as failed (after accepting it) is resent by
# email, through the provider gem's webhook and notification.delivery_failed.
RSpec.describe 'Email backup after a Gupshup failure report', type: :request do
  let(:store) { Spree::Store.default || create(:store) }
  let!(:config) { gupshup_ready_config(store) }
  let!(:user) { create(:user, email: 'asha@example.com', mobile_number: '+919876543210') }
  let(:message_ref) { SecureRandom.uuid }
  let!(:attempt) do
    salt = Spree::OtpAttempt.generate_salt
    Spree::OtpAttempt.create!(store: store, user: user, identifier: '+919876543210', channel: 'whatsapp',
                              code_digest: Spree::OtpAttempt.digest('111111', salt), salt: salt,
                              delivery_status: 'submitted', provider_message_id: 'gs-abc',
                              delivery_message_ref: message_ref, expires_at: 10.minutes.from_now)
  end
  let!(:email_sends) { capture_otp_emails }

  def with_delivery_row
    Spree::NotificationDelivery.create!(store: store, message_ref: message_ref, channel: 'whatsapp',
                                        provider_key: 'gupshup', message_type: 'otp_code',
                                        recipient: '+919876543210', outcome: 'delivered',
                                        provider_message_id: 'gs-abc', attempt_number: 1)
  end

  def failed_event(id: 'gs-abc', reason: 'Number Does Not Exists On WhatsApp')
    { type: 'message-event', payload: { gsId: id, type: 'failed', payload: { code: 1002, reason: reason } } }
  end

  def deliver(body)
    post "/webhooks/gupshup?secret=#{GupshupHelpers::WEBHOOK_SECRET}", params: body.to_json,
                                                                     headers: { 'Content-Type' => 'application/json' }
  end

  it 'sends the code by email when the WhatsApp message failed' do
    with_delivery_row

    deliver(failed_event(reason: 'x' * 300))

    expect(response).to have_http_status(:ok)
    attempt.reload
    expect(attempt.delivery_status).to eq('fallback_sent')
    expect(attempt.fallback_reason.length).to eq(120)
    expect(attempt).to be_expired
    expect(email_sends.map { |s| s[:identifier] }).to eq(['asha@example.com'])
    expect(Spree::OtpAttempt.login.active.last.channel).to eq('email')
  end

  it 'finds codes sent before the provider gem through the OTP resolver' do
    deliver(failed_event)

    expect(response).to have_http_status(:ok)
    expect(attempt.reload.delivery_status).to eq('fallback_sent')
  end

  it 'ignores attempts that are already switched' do
    with_delivery_row
    attempt.update_columns(delivery_status: 'fallback_sent')

    deliver(failed_event)

    expect(email_sends).to be_empty
  end

  it 'marks the attempt failed without email when backup is off' do
    with_delivery_row
    config.update_columns(fallback_channel: 'none')

    deliver(failed_event)

    expect(attempt.reload.delivery_status).to eq('failed')
    expect(email_sends).to be_empty
  end
end
