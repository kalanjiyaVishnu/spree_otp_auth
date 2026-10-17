# frozen_string_literal: true

# Stubs Gupshup HTTP traffic for OTP specs.
#
# The dev container carries a real GUPSHUP_API_KEY, so every engine spec runs
# with the key blanked unless it opts in via `stub_gupshup`. `stub_gupshup`
# fakes Net::HTTP.start for api.gupshup.io and records requests so specs can
# assert on the exact form body that would have been sent.
module GupshupHelpers
  TEMPLATE_UUID = 'c6aecef6-bcb0-4fb1-8100-28c094e3bc6b'
  FakeResponse = Struct.new(:code, :body) do
    def is_a?(klass)
      return code.to_i.between?(200, 299) if klass == Net::HTTPSuccess

      super
    end
  end

  def gupshup_requests
    @gupshup_requests ||= []
  end

  # send_status: 'submitted' (default), any other string, or :timeout.
  # send_http_code: HTTP code returned for the send call.
  # templates: array returned by the template lookup.
  def stub_gupshup(api_key: 'test-gupshup-key', send_status: 'submitted', send_http_code: 202,
                   message_id: SecureRandom.uuid,
                   templates: [{ 'id' => TEMPLATE_UUID, 'elementName' => 'verify_otp', 'status' => 'APPROVED' }])
    allow(Spree::Otp::Provider::GupshupWhatsapp).to receive(:api_key).and_return(api_key)

    fake_http = Object.new
    recorder = gupshup_requests
    fake_http.define_singleton_method(:request) do |req|
      recorder << req
      if req.is_a?(Net::HTTP::Get)
        FakeResponse.new('200', { 'status' => 'success', 'templates' => templates }.to_json)
      else
        raise Net::ReadTimeout if send_status == :timeout

        FakeResponse.new(send_http_code.to_s, { 'status' => send_status, 'messageId' => message_id }.to_json)
      end
    end

    allow(Net::HTTP).to receive(:start).and_wrap_original do |original, host, *args, **kwargs, &block|
      if host == 'api.gupshup.io'
        gupshup_http_options << kwargs
        block.call(fake_http)
      else
        original.call(host, *args, **kwargs, &block)
      end
    end
    fake_http
  end

  def gupshup_http_options
    @gupshup_http_options ||= []
  end

  def gupshup_send_requests
    gupshup_requests.select { |r| r.is_a?(Net::HTTP::Post) }
  end

  def gupshup_lookup_requests
    gupshup_requests.select { |r| r.is_a?(Net::HTTP::Get) }
  end

  def gupshup_ready_config(store, **attrs)
    cfg = Spree::OtpConfiguration.default_for(store)
    cfg.assign_attributes(
      {
        active_channel: 'whatsapp',
        fallback_channel: 'email',
        gupshup_source_number: '919000000001',
        gupshup_app_name: 'OntodiApp',
        gupshup_app_id: 'app-123',
        gupshup_template_name: 'verify_otp'
      }.merge(attrs)
    )
    # Skip validation: the API key is blanked by default in specs, and the
    # "WhatsApp needs a key" rule has its own coverage.
    cfg.save!(validate: false)
    cfg
  end
end

RSpec.configure do |config|
  config.include GupshupHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  config.before do
    allow(Spree::Otp::Provider::GupshupWhatsapp).to receive(:api_key).and_return(nil)
    # The test env uses :null_store; template-id caching needs a real store.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end
end
