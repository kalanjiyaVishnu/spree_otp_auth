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
        expect(response.body).to include('otp_configuration[msg91_whatsapp_template_id]')
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
        expect(response.body).to include('wa_template_456')
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
            active_channel: 'whatsapp',
            msg91_auth_key: '' # Blank - should retain original_secure_key
          }
        }

        expect(response).to redirect_to('/admin/otp_configuration/edit')
        cfg.reload
        expect(cfg.active_channel).to eq('whatsapp')
        expect(cfg.msg91_auth_key).to eq('original_secure_key')
      end

      it 'isolates configuration between different stores' do
        other_store = create(:store, name: 'Other Store', code: 'other', url: 'other.example.com')
        other_cfg = Spree::OtpConfiguration.create!(
          store: other_store,
          active_channel: 'whatsapp',
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
        expect(other_cfg.active_channel).to eq('whatsapp')
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
end
