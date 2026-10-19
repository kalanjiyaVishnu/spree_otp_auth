# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::OtpMailer, type: :mailer do
  let(:store) { @default_store }

  describe '#send_otp' do
    context 'without a custom email template' do
      it 'renders default responsive email with OTP code' do
        mail = described_class.send_otp(
          store: store,
          to: 'customer@example.com',
          code: '654321',
          expiry_minutes: 10
        )

        expect(mail.to).to eq(['customer@example.com'])
        expect(mail.subject).to include('654321')
        expect(mail.subject).to include(store.name)
        expect(mail.body.encoded).to include('654321')
      end
    end

    context 'with a configured Spree::EmailTemplate' do
      prepend_before { skip 'needs an app email template model' unless SpreeOtpAuth.email_template_model }

      let!(:template) do
        Spree::EmailTemplate.create!(
          store: store,
          name: 'Custom OTP Notification',
          slug: 'custom_otp_notification',
          category: 'transactional',
          subject: 'Your code is {{OTP_CODE}} for {{store_name}}',
          body_html: '<h1>Code: {{otp_code}}</h1><p>Expires in {{EXPIRY_MINUTES}} mins for {{STORE_NAME}}</p>'
        )
      end

      before do
        config = Spree::OtpConfiguration.find_or_initialize_by(store: store)
        config.update!(
          active_channel: 'email',
          email_template: template
        )
      end

      it 'interpolates both uppercase and lowercase variables into custom template' do
        mail = described_class.send_otp(
          store: store,
          to: 'shopper@example.com',
          code: '123456',
          expiry_minutes: 15
        )

        expect(mail.to).to eq(['shopper@example.com'])
        expect(mail.subject).to eq("Your code is 123456 for #{store.name}")
        expect(mail.body.encoded).to include("Code: 123456")
        expect(mail.body.encoded).to include("Expires in 15 mins for #{store.name}")
      end
    end
  end
end
