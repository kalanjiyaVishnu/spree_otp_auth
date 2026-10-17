# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Otp::Provider::GupshupWhatsapp do
  let(:store) { create(:store) }
  let!(:config) { gupshup_ready_config(store) }
  let(:provider) { described_class.new(store) }
  let(:code) { '482913' }

  def send_body
    URI.decode_www_form(gupshup_send_requests.last.body).to_h
  end

  context 'when Gupshup accepts the message' do
    before { stub_gupshup(message_id: 'gs-msg-1') }

    it 'returns success with the Gupshup message id' do
      result = provider.send_otp(identifier: '+919876543210', code: code)

      expect(result).to be_success
      expect(result.channel).to eq('whatsapp')
      expect(result.message_id).to eq('gs-msg-1')
    end

    it 'posts the template form body Gupshup expects' do
      provider.send_otp(identifier: '+919876543210', code: code)

      req = gupshup_send_requests.last
      expect(req.path).to eq('/wa/api/v1/template/msg')
      expect(req['apikey']).to eq('test-gupshup-key')
      expect(req['Content-Type']).to eq('application/x-www-form-urlencoded')
      expect(send_body).to include(
        'channel' => 'whatsapp',
        'source' => '919000000001',
        'destination' => '919876543210',
        'src.name' => 'OntodiApp'
      )
      expect(JSON.parse(send_body['template'])).to eq('id' => GupshupHelpers::TEMPLATE_UUID, 'params' => [code])
    end

    it 'uses 5 second timeouts over TLS' do
      provider.send_otp(identifier: '+919876543210', code: code)

      expect(gupshup_http_options.last).to include(use_ssl: true, open_timeout: 5, read_timeout: 5)
    end

    it 'looks the template up by name once and caches the id' do
      provider.send_otp(identifier: '+919876543210', code: code)
      described_class.new(store).send_otp(identifier: '+919876543210', code: code)

      expect(gupshup_lookup_requests.size).to eq(1)
      expect(gupshup_lookup_requests.first.path).to eq('/wa/app/app-123/template?templateStatus=APPROVED')
      expect(gupshup_send_requests.size).to eq(2)
    end

    it 'skips the lookup when a template id override is set' do
      override = '11111111-2222-3333-4444-555555555555'
      config.update!(gupshup_template_id: override)

      provider.send_otp(identifier: '+919876543210', code: code)

      expect(gupshup_lookup_requests).to be_empty
      expect(JSON.parse(send_body['template'])['id']).to eq(override)
    end

    it 'looks the template up again after the cache is cleared' do
      provider.send_otp(identifier: '+919876543210', code: code)
      described_class.clear_template_cache(store)
      provider.send_otp(identifier: '+919876543210', code: code)

      expect(gupshup_lookup_requests.size).to eq(2)
    end

    it 'sends a fixed test code for the admin test' do
      result = provider.test_send(phone: '9876543210')

      expect(result).to be_success
      expect(JSON.parse(send_body['template'])['params']).to eq([described_class::TEST_CODE])
      expect(send_body['destination']).to eq('919876543210')
    end
  end

  context 'when the template name is not approved in Gupshup' do
    before { stub_gupshup(templates: [{ 'id' => 'x', 'elementName' => 'other', 'status' => 'APPROVED' }]) }

    it 'fails with template_not_found and sends nothing' do
      result = provider.send_otp(identifier: '+919876543210', code: code)

      expect(result).to be_failure
      expect(result.error_message).to eq('template_not_found')
      expect(gupshup_send_requests).to be_empty
    end
  end

  context 'when Gupshup rejects the request' do
    it 'fails on a non-2xx response' do
      stub_gupshup(send_http_code: 401, send_status: 'error')

      result = provider.send_otp(identifier: '+919876543210', code: code)

      expect(result).to be_failure
      expect(result.error_message).to eq('HTTP 401')
    end

    it 'fails when the status is not submitted' do
      stub_gupshup(send_status: 'error')

      expect(provider.send_otp(identifier: '+919876543210', code: code)).to be_failure
    end

    it 'fails on a timeout' do
      stub_gupshup(send_status: :timeout)

      result = provider.send_otp(identifier: '+919876543210', code: code)

      expect(result).to be_failure
      expect(result.error_message).to eq('timeout')
    end
  end

  it 'never puts the code or API key in error messages or logs' do
    stub_gupshup(api_key: 'super-secret-key', send_http_code: 500, send_status: 'error')
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))

    result = provider.send_otp(identifier: '+919876543210', code: code)

    expect(result.error_message).not_to include(code)
    expect(result.error_message).not_to include('super-secret-key')
    expect(log.string).not_to include(code)
    expect(log.string).not_to include('super-secret-key')
  end

  context 'without GUPSHUP_API_KEY' do
    it 'simulates delivery outside production' do
      result = provider.send_otp(identifier: '+919876543210', code: code)

      expect(result).to be_success
      expect(result.message_id).to start_with('sim-gs-')
    end

    it 'fails in production' do
      allow(Rails.env).to receive(:production?).and_return(true)

      result = provider.send_otp(identifier: '+919876543210', code: code)

      expect(result).to be_failure
      expect(result.error_message).to eq('provider_not_configured')
    end
  end
end
