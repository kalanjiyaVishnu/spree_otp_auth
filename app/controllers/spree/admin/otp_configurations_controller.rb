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
          flash[:success] = Spree.t('otp_auth.admin.update_success', default: 'OTP authentication settings updated successfully.')
          redirect_to spree.edit_admin_otp_configuration_path, status: :see_other
        else
          flash.now[:error] = @otp_configuration.errors.full_messages.join(', ')
          render :edit, status: :unprocessable_content
        end
      end

      private

      def model_class
        Spree::OtpConfiguration
      end

      def load_otp_configuration
        @otp_configuration = Spree::OtpConfiguration.find_or_initialize_by(store: current_store)
        if @otp_configuration.new_record?
          @otp_configuration.active_channel = 'email'
          @otp_configuration.fallback_channel = 'none'
          @otp_configuration.otp_length = 6
          @otp_configuration.otp_expiry_seconds = 600
          @otp_configuration.resend_cooldown_seconds = 30
          @otp_configuration.fallback_delay_seconds = 20
        end
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
          :msg91_sender_id
        )
      end
    end
  end
end
