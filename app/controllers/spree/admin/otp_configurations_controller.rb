# frozen_string_literal: true

module Spree
  module Admin
    class OtpConfigurationsController < Spree::Admin::BaseController
      before_action :load_otp_configuration

      def edit
        authorize! :manage, Spree::OtpConfiguration
      end

      def update
        authorize! :manage, Spree::OtpConfiguration

        attrs = otp_configuration_params
        # Retain existing encrypted key if blank value submitted
        attrs.delete(:msg91_auth_key) if attrs[:msg91_auth_key].blank?
        attrs[:email_template_id] = nil if attrs[:email_template_id].blank?

        if @otp_configuration.update(attrs)
          Spree::Otp::Provider::GupshupWhatsapp.clear_template_cache(current_store)
          flash[:success] = Spree.t('otp_auth.admin.update_success', default: 'OTP authentication settings updated successfully.')
          redirect_to spree.edit_admin_otp_configuration_path, status: :see_other
        else
          flash.now[:error] = @otp_configuration.errors.full_messages.join(', ')
          render :edit, status: :unprocessable_content
        end
      end

      # Sends a real verify_otp message with a fixed test code using the saved
      # settings. Creates no OtpAttempt and bypasses the customer rate limiter.
      def test_whatsapp
        authorize! :manage, Spree::OtpConfiguration

        phone = params[:test_phone].to_s.strip
        if phone.blank?
          flash[:error] = 'Please enter a phone number to send the test to.'
          return redirect_to(spree.edit_admin_otp_configuration_path, status: :see_other)
        end

        result = Spree::Otp::Provider::GupshupWhatsapp.new(current_store).test_send(phone: phone)
        masked = Spree::Otp::Identity.mask_phone(Spree::Otp::Identity.normalize_phone(phone) || phone)

        if result.success?
          flash[:success] = "Test WhatsApp sent to #{masked} (message ID #{result.message_id})."
        else
          flash[:error] = "Test WhatsApp to #{masked} failed: #{result.error_message}."
        end

        redirect_to spree.edit_admin_otp_configuration_path, status: :see_other
      end

      private

      def model_class
        Spree::OtpConfiguration
      end

      def load_otp_configuration
        @otp_configuration = Spree::OtpConfiguration.default_for(current_store)
      end

      def otp_configuration_params
        params.require(:otp_configuration).permit(
          :active_channel,
          :fallback_channel,
          :email_template_id,
          :otp_length,
          :otp_expiry_seconds,
          :resend_cooldown_seconds,
          :fallback_delay_seconds,
          :msg91_auth_key,
          :msg91_sms_template_id,
          :msg91_whatsapp_template_id,
          :msg91_sender_id,
          :gupshup_source_number,
          :gupshup_app_name,
          :gupshup_app_id,
          :gupshup_template_name,
          :gupshup_template_id
        )
      end
    end
  end
end
