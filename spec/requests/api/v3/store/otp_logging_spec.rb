# frozen_string_literal: true

require 'spec_helper'
require 'spree/api/testing_support/v3/base'

# FR-003 / FR-012 / SC-007: no OTP code, Gupshup API key or webhook secret may
# reach the logs, including Rails' own "Parameters:" request lines.
RSpec.describe 'OTP log safety', type: :request do
  include_context 'API v3 Store authenticated'

  let(:code) { '738201' }
  let(:email_code) { '615204' }
  let(:gupshup_key) { 'gs-live-key-do-not-log' }
  let(:webhook_secret) { 'hook-secret-do-not-log' }
  let(:headers) { api_key_headers.merge('Content-Type' => 'application/json') }
  let(:log) { StringIO.new }
  let(:sink) { ActiveSupport::Logger.new(log) }

  before do
    gupshup_ready_config(store)
    stub_gupshup(api_key: gupshup_key, message_id: 'gs-log-1')
    stub_const('ENV', ENV.to_h.merge('GUPSHUP_WEBHOOK_SECRET' => webhook_secret))
    allow(Spree::Otp::Generate).to receive(:generate_code).and_return(code, email_code, code, code)
    allow_any_instance_of(Spree::Otp::Provider::Email).to receive(:send_otp)
      .and_return(Spree::Otp::Provider::Result.new(success: true, channel: 'email', message_id: 'mail-1'))
    create(:user, email: 'emailonly@example.com', mobile_number: nil)

    sink.level = :debug
    Rails.logger.broadcast_to(sink)
  end

  after { Rails.logger.stop_broadcasting_to(sink) }

  it 'keeps codes, the API key and the webhook secret out of the logs' do
    post '/api/v3/store/otp/request', params: { identifier: '9876543210', email: 'emailonly@example.com' }.to_json, headers: headers
    post '/api/v3/store/otp/verify', params: { identifier: '9876543210', code: '000000', email_code: '111111' }.to_json, headers: headers
    post '/api/v3/store/otp/verify', params: { identifier: '9876543210', code: code, email_code: email_code }.to_json, headers: headers
    post "/webhooks/gupshup?secret=#{webhook_secret}",
         params: { type: 'message-event', payload: { gsId: 'gs-log-1', type: 'failed' } }.to_json,
         headers: { 'Content-Type' => 'application/json' }

    expect(log.string).to include('/api/v3/store/otp/verify') # the requests were logged at all
    [code, email_code, '000000', '111111', gupshup_key, webhook_secret].each do |secret|
      expect(log.string).not_to include(secret)
    end
  end
end
