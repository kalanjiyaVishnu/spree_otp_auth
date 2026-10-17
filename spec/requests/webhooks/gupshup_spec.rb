# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gupshup delivery webhook', type: :request do
  let(:store) { Spree::Store.default || create(:store) }
  let(:secret) { 'webhook-secret-123' }
  let!(:config) { gupshup_ready_config(store) }
  let!(:user) { create(:user, email: 'asha@example.com', mobile_number: '+919876543210') }
  let!(:attempt) do
    salt = Spree::OtpAttempt.generate_salt
    Spree::OtpAttempt.create!(store: store, user: user, identifier: '+919876543210', channel: 'whatsapp',
                              code_digest: Spree::OtpAttempt.digest('111111', salt), salt: salt,
                              delivery_status: 'submitted', provider_message_id: 'gs-abc',
                              expires_at: 10.minutes.from_now)
  end
  let(:email_sends) { [] }

  before do
    stub_const('ENV', ENV.to_h.merge('GUPSHUP_WEBHOOK_SECRET' => secret))
    sends = email_sends
    allow_any_instance_of(Spree::Otp::Provider::Email).to receive(:send_otp) do |_p, identifier:, code:, metadata: {}|
      sends << identifier
      Spree::Otp::Provider::Result.new(success: true, channel: 'email', message_id: 'mail-1')
    end
  end

  def failed_event(id: 'gs-abc', key: 'gsId', reason: 'Number Does Not Exists On WhatsApp')
    { type: 'message-event', payload: { key => id, type: 'failed', payload: { code: 1002, reason: reason } } }
  end

  def deliver(body, secret_param: secret)
    post "/webhooks/gupshup?secret=#{secret_param}", params: body.to_json, headers: { 'Content-Type' => 'application/json' }
  end

  it 'returns 404 for a wrong secret and changes nothing' do
    deliver(failed_event, secret_param: 'nope')

    expect(response).to have_http_status(:not_found)
    expect(attempt.reload.delivery_status).to eq('submitted')
  end

  it 'returns 404 when no secret is configured' do
    stub_const('ENV', ENV.to_h.merge('GUPSHUP_WEBHOOK_SECRET' => ''))

    deliver(failed_event, secret_param: '')

    expect(response).to have_http_status(:not_found)
  end

  it 'sends the code by email when the WhatsApp message failed' do
    deliver(failed_event(reason: 'x' * 300))

    expect(response).to have_http_status(:ok)
    attempt.reload
    expect(attempt.delivery_status).to eq('fallback_sent')
    expect(attempt.fallback_reason.length).to eq(120)
    expect(attempt).to be_expired
    expect(email_sends).to eq(['asha@example.com'])
    expect(Spree::OtpAttempt.login.active.last.channel).to eq('email')
  end

  it 'accepts the message id under payload.id' do
    deliver(failed_event(key: 'id'))

    expect(attempt.reload.delivery_status).to eq('fallback_sent')
  end

  it 'ignores events that are not failures' do
    deliver({ type: 'message-event', payload: { gsId: 'gs-abc', type: 'delivered' } })

    expect(response).to have_http_status(:ok)
    expect(attempt.reload.delivery_status).to eq('submitted')
  end

  it 'ignores unknown message ids' do
    deliver(failed_event(id: 'gs-unknown'))

    expect(response).to have_http_status(:ok)
    expect(email_sends).to be_empty
  end

  it 'ignores attempts that are already verified or switched' do
    attempt.update_columns(delivery_status: 'fallback_sent')
    deliver(failed_event)

    expect(email_sends).to be_empty
  end

  it 'marks the attempt failed without email when backup is off' do
    config.update_columns(fallback_channel: 'none')

    deliver(failed_event)

    expect(attempt.reload.delivery_status).to eq('failed')
    expect(email_sends).to be_empty
  end
end
