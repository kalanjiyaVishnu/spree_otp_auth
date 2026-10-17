# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin OTP Configurations', type: :request do
  let(:store) { @default_store }
  let(:admin) { create(:admin_user) }

  context 'when unauthenticated' do
    it 'redirects to admin login' do
      get '/admin/otp_configuration/edit'
      expect(response).to redirect_to('/admin_user/sign_in')
    end
  end

  context 'when authenticated as admin' do
    before { login_as(admin, scope: :admin_user) }
    after { Warden.test_reset! }

    describe 'GET /admin/otp_configuration/edit' do
      it 'renders the OTP configuration page with 200 OK' do
        get '/admin/otp_configuration/edit'

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('OTP Authentication')
        expect(response.body).to include('otp_configuration[active_channel]')
        expect(response.body).to include('otp_configuration[msg91_auth_key]')
        expect(response.body).to include('otp_configuration[msg91_sms_template_id]')
        expect(response.body).not_to include('otp_configuration[msg91_whatsapp_template_id]')
      end

      it 'prefills existing configuration for the store' do
        template = Spree::EmailTemplate.create!(
          store: store,
          name: 'Custom OTP Email',
          slug: 'custom_otp_email',
          subject: 'Your code is {{otp_code}}',
          body_html: '<p>Code: {{otp_code}}</p>'
        )

        Spree::OtpConfiguration.create!(
          store: store,
          active_channel: 'email',
          fallback_channel: 'whatsapp',
          email_template: template,
          otp_length: 6,
          otp_expiry_seconds: 300,
          resend_cooldown_seconds: 45,
          fallback_delay_seconds: 25,
          msg91_auth_key: 'super_secret_auth_key',
          msg91_sms_template_id: 'sms_template_123',
          msg91_whatsapp_template_id: 'wa_template_456',
          msg91_sender_id: 'ONTODI'
        )

        get '/admin/otp_configuration/edit'

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('sms_template_123')
        expect(response.body).to include('Custom OTP Email')
        expect(response.body).to include('••••••••') # Masked secret key placeholder
      end
    end

    describe 'PATCH /admin/otp_configuration' do
      it 'updates OTP configuration for current_store including fallback and template' do
        template = Spree::EmailTemplate.create!(
          store: store,
          name: 'Updated Template',
          slug: 'updated_template',
          subject: 'Code {{otp_code}}',
          body_html: '<h1>{{otp_code}}</h1>'
        )

        patch '/admin/otp_configuration', params: {
          otp_configuration: {
            active_channel: 'email',
            fallback_channel: 'whatsapp',
            email_template_id: template.id,
            otp_length: 6,
            otp_expiry_seconds: 300,
            resend_cooldown_seconds: 45,
            fallback_delay_seconds: 25,
            msg91_auth_key: 'new_msg91_auth_key',
            msg91_sms_template_id: 'dlt_template_999',
            msg91_whatsapp_template_id: 'wa_template_888',
            msg91_sender_id: 'TESTID'
          }
        }

        expect(response).to redirect_to('/admin/otp_configuration/edit')
        expect(flash[:success]).to be_present

        cfg = Spree::OtpConfiguration.find_by!(store: store)
        expect(cfg.active_channel).to eq('email')
        expect(cfg.fallback_channel).to eq('whatsapp')
        expect(cfg.email_template_id).to eq(template.id)
        expect(cfg.otp_expiry_seconds).to eq(300)
        expect(cfg.resend_cooldown_seconds).to eq(45)
        expect(cfg.fallback_delay_seconds).to eq(25)
        expect(cfg.msg91_sms_template_id).to eq('dlt_template_999')
        expect(cfg.msg91_whatsapp_template_id).to eq('wa_template_888')
        expect(cfg.msg91_sender_id).to eq('TESTID')
        expect(cfg.msg91_auth_key).to eq('new_msg91_auth_key')
      end

      it 'retains existing encrypted auth key if blank submitted' do
        cfg = Spree::OtpConfiguration.create!(
          store: store,
          active_channel: 'email',
          msg91_auth_key: 'original_secure_key'
        )

        patch '/admin/otp_configuration', params: {
          otp_configuration: {
            active_channel: 'mobile',
            msg91_auth_key: '' # Blank - should retain original_secure_key
          }
        }

        expect(response).to redirect_to('/admin/otp_configuration/edit')
        cfg.reload
        expect(cfg.active_channel).to eq('mobile')
        expect(cfg.msg91_auth_key).to eq('original_secure_key')
      end

      it 'isolates configuration between different stores' do
        other_store = create(:store, name: 'Other Store', code: 'other', url: 'other.example.com')
        other_cfg = Spree::OtpConfiguration.create!(
          store: other_store,
          active_channel: 'email',
          msg91_auth_key: 'other_store_key'
        )

        patch '/admin/otp_configuration', params: {
          otp_configuration: {
            active_channel: 'mobile',
            msg91_auth_key: 'store_a_key'
          }
        }

        expect(response).to redirect_to('/admin/otp_configuration/edit')

        store_a_cfg = Spree::OtpConfiguration.find_by!(store: store)
        expect(store_a_cfg.active_channel).to eq('mobile')
        expect(store_a_cfg.msg91_auth_key).to eq('store_a_key')

        other_cfg.reload
        expect(other_cfg.active_channel).to eq('email')
        expect(other_cfg.msg91_auth_key).to eq('other_store_key')
      end

      it 'renders unprocessable_content on invalid parameters' do
        patch '/admin/otp_configuration', params: {
          otp_configuration: {
            active_channel: 'invalid_channel',
            otp_length: 5 # Invalid length
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('Active channel is not included in the list')
      end
    end
  end

  describe 'WhatsApp (Gupshup) settings' do
    before { login_as(admin, scope: :admin_user) }
    after { Warden.test_reset! }

    let(:gupshup_params) do
      {
        gupshup_source_number: '91 90000 00001',
        gupshup_app_name: 'OntodiApp',
        gupshup_app_id: 'app-123',
        gupshup_template_name: 'verify_otp',
        gupshup_template_id: ''
      }
    end

    it 'shows the Gupshup fields, email backup toggle and a missing API key' do
      get '/admin/otp_configuration/edit'

      expect(response.body).to include('otp_configuration[gupshup_source_number]')
      expect(response.body).to include('otp_configuration[gupshup_app_name]')
      expect(response.body).to include('otp_configuration[gupshup_app_id]')
      expect(response.body).to include('otp_configuration[gupshup_template_name]')
      expect(response.body).to include('otp_configuration[gupshup_template_id]')
      expect(response.body).to include('value="verify_otp"')
      expect(response.body).to include('otp_configuration[fallback_channel]')
      expect(response.body).to include('Missing')
      expect(response.body).to include('test_phone')
    end

    it 'shows the API key as configured without revealing it, and masks the webhook secret' do
      allow(Spree::Otp::Provider::GupshupWhatsapp).to receive(:api_key).and_return('live-key-should-not-render')
      stub_const('ENV', ENV.to_h.merge('GUPSHUP_WEBHOOK_SECRET' => 'abcdef123456wxyz'))

      get '/admin/otp_configuration/edit'

      expect(response.body).to include('Configured')
      expect(response.body).not_to include('live-key-should-not-render')
      expect(response.body).not_to include('abcdef123456wxyz')
      expect(response.body).to include('/webhooks/gupshup?secret=')
      expect(response.body).to include('wxyz')
    end

    it 'saves the Gupshup fields and normalizes the source number' do
      patch '/admin/otp_configuration', params: { otp_configuration: gupshup_params.merge(active_channel: 'email') }

      expect(response).to redirect_to('/admin/otp_configuration/edit')
      cfg = Spree::OtpConfiguration.find_by!(store: store)
      expect(cfg).to have_attributes(gupshup_source_number: '919000000001', gupshup_app_name: 'OntodiApp',
                                     gupshup_app_id: 'app-123', gupshup_template_name: 'verify_otp',
                                     gupshup_template_id: nil)
    end

    it 'refuses to switch to WhatsApp while settings are missing and names each one' do
      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'whatsapp' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('API key (GUPSHUP_API_KEY in the server environment)')
      expect(response.body).to include('source number')
      expect(response.body).to include('app name')
      expect(response.body).to include('app ID (or a template ID)')
    end

    it 'switches to WhatsApp when ready and clears the cached template id' do
      allow(Spree::Otp::Provider::GupshupWhatsapp).to receive(:api_key).and_return('test-gupshup-key')
      allow(Spree::Otp::Provider::GupshupWhatsapp).to receive(:clear_template_cache).and_call_original

      patch '/admin/otp_configuration', params: { otp_configuration: gupshup_params.merge(active_channel: 'whatsapp', fallback_channel: 'email') }

      expect(response).to redirect_to('/admin/otp_configuration/edit')
      expect(Spree::OtpConfiguration.find_by!(store: store)).to have_attributes(active_channel: 'whatsapp', fallback_channel: 'email')
      expect(Spree::Otp::Provider::GupshupWhatsapp).to have_received(:clear_template_cache).with(store)
    end

    it 'turns the email backup off' do
      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'email', fallback_channel: 'none' } }

      expect(Spree::OtpConfiguration.find_by!(store: store).fallback_channel).to eq('none')
    end

    describe 'POST /admin/otp_configuration/test_whatsapp' do
      before { gupshup_ready_config(store) }

      it 'sends a test message and reports the message id' do
        stub_gupshup(message_id: 'gs-test-1')

        post '/admin/otp_configuration/test_whatsapp', params: { test_phone: '9876543210' }

        expect(response).to redirect_to('/admin/otp_configuration/edit')
        expect(response).to have_http_status(:see_other)
        expect(flash[:success]).to include('+91 98*** **210')
        expect(flash[:success]).to include('gs-test-1')
        expect(gupshup_send_requests.size).to eq(1)
        expect(Spree::OtpAttempt.count).to eq(0)
      end

      it 'reports the provider reason on failure' do
        stub_gupshup(templates: [])

        post '/admin/otp_configuration/test_whatsapp', params: { test_phone: '9876543210' }

        expect(flash[:error]).to include('template_not_found')
      end

      it 'asks for a phone number' do
        post '/admin/otp_configuration/test_whatsapp', params: { test_phone: '' }

        expect(flash[:error]).to be_present
      end

      it 'never puts the API key in the flash' do
        stub_gupshup(api_key: 'secret-key-xyz', send_http_code: 401, send_status: 'error')

        post '/admin/otp_configuration/test_whatsapp', params: { test_phone: '9876543210' }

        expect(flash[:error]).not_to include('secret-key-xyz')
        expect(flash[:error]).to include('HTTP 401')
      end
    end
  end
end
