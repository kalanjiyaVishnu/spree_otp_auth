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
          :fallback_delay_seconds
        )
      end
    end
  end
end
