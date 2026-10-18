# frozen_string_literal: true

# Sets up Gupshup as the store's WhatsApp provider for OTP specs and fakes its
# HTTP traffic through SpreeNotificationProviders::Http (see the provider
# gem's provider_http_helpers). `capture_otp_emails` records email codes
# instead of rendering and queueing the mailer.
module GupshupHelpers
  TEMPLATE_UUID = 'c6aecef6-bcb0-4fb1-8100-28c094e3bc6b'
  API_KEY = 'test-gupshup-key'
  WEBHOOK_SECRET = 'webhook-secret-123'

  def gupshup_requests
    provider_http_requests.select { |request| request[:url].to_s.include?('gupshup') }
  end

  def gupshup_send_requests
    gupshup_requests.select { |request| request[:method] == :post }
  end

  def gupshup_lookup_requests
    gupshup_requests.select { |request| request[:method] == :get }
  end

  # send_status: 'submitted' (default), any other string, or :timeout (the
  # send may have gone out, so the router reports :unknown).
  # send_http_code: HTTP code returned for the send call.
  # templates: array returned by the template lookup.
  def stub_gupshup(send_status: 'submitted', send_http_code: 202, message_id: SecureRandom.uuid,
                   templates: [{ 'id' => TEMPLATE_UUID, 'elementName' => 'verify_otp', 'status' => 'APPROVED' }])
    stub_provider_http do |method, _url, _opts|
      if method == :get
        [200, { 'status' => 'success', 'templates' => templates }]
      elsif send_status == :timeout
        [0, Net::ReadTimeout]
      else
        [send_http_code, { 'status' => send_status, 'messageId' => message_id }]
      end
    end
  end

  # Gupshup set up in Notification providers → WhatsApp; the login channel and
  # email backup stay on the OTP configuration, which is returned.
  def gupshup_ready_config(store, api_key: API_KEY, webhook_secret: WEBHOOK_SECRET, **otp_attrs)
    entry = Spree::NotificationChannelProvider.find_or_initialize_by(store_id: store.id, channel: 'whatsapp',
                                                                     provider_key: 'gupshup')
    entry.enabled = true
    entry.settings = { 'source_number' => '919000000001', 'app_name' => 'OntodiApp', 'app_id' => 'app-123' }
    entry.templates = { 'otp_code' => 'verify_otp' }
    entry.save!

    provider_config = entry.provider_config
    provider_config.secret_settings = { 'api_key' => api_key, 'webhook_secret' => webhook_secret }.to_json
    provider_config.save!

    cfg = Spree::OtpConfiguration.default_for(store)
    cfg.assign_attributes({ active_channel: 'whatsapp', fallback_channel: 'email' }.merge(otp_attrs))
    cfg.save!(validate: false)
    cfg
  end

  def remove_gupshup(store)
    Spree::NotificationChannelProvider.where(store_id: store.id, provider_key: 'gupshup').destroy_all
  end

  # Records email codes as { identifier:, code: } and reports them sent.
  def capture_otp_emails(result: :sent)
    sends = []
    allow(Spree::Otp::Delivery).to receive(:send_email) do |store:, to:, code:, expiry_minutes:|
      sends << { identifier: to, code: code, store: store, expiry_minutes: expiry_minutes }
      Spree::Otp::Delivery::Outcome.new(status: result, message_id: "mail-#{sends.size}",
                                        error_message: (result == :failed ? 'smtp_auth' : nil))
    end
    sends
  end
end

RSpec.configure do |config|
  config.include GupshupHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  config.before do
    # The test env uses :null_store; template-id caching needs a real store.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end
end
