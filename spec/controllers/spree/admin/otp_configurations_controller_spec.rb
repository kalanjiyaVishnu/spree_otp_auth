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
      it 'renders the OTP settings without any provider credentials' do
        get '/admin/otp_configuration/edit'

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('OTP Authentication')
        expect(response.body).to include('otp_configuration[active_channel]')
        expect(response.body).not_to include('otp_configuration[msg91_')
        expect(response.body).not_to include('otp_configuration[gupshup_')
      end

      it 'prefills existing configuration for the store' do
        template = Spree::EmailTemplate.create!(
          store: store,
          name: 'Custom OTP Email',
          slug: 'custom_otp_email',
          subject: 'Your code is {{otp_code}}',
          body_html: '<p>Code: {{otp_code}}</p>'
        )
        Spree::OtpConfiguration.create!(store: store, active_channel: 'email', fallback_channel: 'whatsapp',
                                        email_template: template, otp_length: 6, otp_expiry_seconds: 300,
                                        resend_cooldown_seconds: 45, fallback_delay_seconds: 25)

        get '/admin/otp_configuration/edit'

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Custom OTP Email')
        expect(response.body).to include('value="300"')
      end
    end

    describe 'PATCH /admin/otp_configuration' do
      it 'updates OTP configuration for current_store including fallback and template' do
        template = Spree::EmailTemplate.create!(store: store, name: 'Updated Template', slug: 'updated_template',
                                                subject: 'Code {{otp_code}}', body_html: '<h1>{{otp_code}}</h1>')

        patch '/admin/otp_configuration', params: {
          otp_configuration: {
            active_channel: 'email', fallback_channel: 'whatsapp', email_template_id: template.id,
            otp_length: 6, otp_expiry_seconds: 300, resend_cooldown_seconds: 45, fallback_delay_seconds: 25,
            msg91_auth_key: 'ignored'
          }
        }

        expect(response).to redirect_to('/admin/otp_configuration/edit')
        expect(flash[:success]).to be_present
        cfg = Spree::OtpConfiguration.find_by!(store: store)
        expect(cfg).to have_attributes(active_channel: 'email', fallback_channel: 'whatsapp', email_template_id: template.id,
                                       otp_expiry_seconds: 300, resend_cooldown_seconds: 45, fallback_delay_seconds: 25)
        expect(cfg.msg91_auth_key).to be_nil
      end

      it 'isolates configuration between different stores' do
        other_store = create(:store, name: 'Other Store', code: 'other', url: 'other.example.com')
        other_cfg = Spree::OtpConfiguration.create!(store: other_store, active_channel: 'email', otp_length: 4)

        patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'email', otp_length: 6 } }

        expect(Spree::OtpConfiguration.find_by!(store: store).otp_length).to eq(6)
        expect(other_cfg.reload.otp_length).to eq(4)
      end

      it 'renders unprocessable_content on invalid parameters' do
        patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'invalid_channel', otp_length: 5 } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('Active channel is not included in the list')
      end
    end
  end

  describe 'provider readiness' do
    before { login_as(admin, scope: :admin_user) }
    after { Warden.test_reset! }

    it 'says WhatsApp is not set up and links to its Notification providers tab' do
      get '/admin/otp_configuration/edit'

      expect(response.body).to include('Not set up')
      expect(response.body).to include('Missing: a WhatsApp provider')
      expect(response.body).to include('/admin/notification_providers?channel=whatsapp')
    end

    it 'says Ready when a WhatsApp provider can send login codes' do
      gupshup_ready_config(store, active_channel: 'email')

      get '/admin/otp_configuration/edit'

      expect(response.body).to match(%r{id="otp-channel-status-whatsapp".*?Ready.*?Gupshup}m)
    end

    it 'refuses to switch to WhatsApp while the provider is missing inputs and says where to fix them' do
      gupshup_ready_config(store, active_channel: 'email')
      Spree::NotificationChannelProvider.find_by!(store: store, provider_key: 'gupshup')
                                        .update!(settings: { 'app_name' => 'x', 'app_id' => 'a' })

      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'whatsapp' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Source number')
      expect(response.body).to include('Set this up in Settings → Notification providers')
    end

    it 'refuses WhatsApp when the provider is disabled' do
      gupshup_ready_config(store, active_channel: 'email')
      Spree::NotificationChannelProvider.find_by!(store: store, provider_key: 'gupshup').update!(enabled: false)

      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'whatsapp' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('an enabled WhatsApp provider')
    end

    it 'refuses WhatsApp when no provider has a login code template' do
      gupshup_ready_config(store, active_channel: 'email')
      Spree::NotificationChannelProvider.find_by!(store: store, provider_key: 'gupshup').update!(templates: {})

      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'whatsapp' } }

      expect(response.body).to include('a &quot;Login code&quot; template')
    end

    it 'switches to WhatsApp when a provider is ready' do
      gupshup_ready_config(store, active_channel: 'email')

      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'whatsapp', fallback_channel: 'email' } }

      expect(response).to redirect_to('/admin/otp_configuration/edit')
      expect(Spree::OtpConfiguration.find_by!(store: store).active_channel).to eq('whatsapp')
    end

    it 'refuses SMS until an SMS provider is ready' do
      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'mobile' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('an SMS provider')
    end

    it 'turns the email backup off' do
      patch '/admin/otp_configuration', params: { otp_configuration: { active_channel: 'email', fallback_channel: 'none' } }

      expect(Spree::OtpConfiguration.find_by!(store: store).fallback_channel).to eq('none')
    end

    it 'has no test send route' do
      post '/admin/otp_configuration/test_whatsapp', params: { test_phone: '9876543210' }

      expect(response).to have_http_status(:not_found)
    end
  end
end
