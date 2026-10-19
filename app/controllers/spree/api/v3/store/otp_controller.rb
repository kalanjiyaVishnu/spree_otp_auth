# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        class OtpController < Store::BaseController
          skip_before_action :authenticate_user, only: [:request_otp, :verify, :resend, :fallback, :delivery_status]
          before_action :require_authentication!, only: [:update_mobile]

          # POST /api/v3/store/otp/verify
          def verify
            identifier = params[:identifier]
            code = params[:code]

            if identifier.blank? || code.blank?
              return render_error(
                code: 'missing_parameter',
                message: 'Identifier and code are required.',
                status: :unprocessable_entity
              )
            end

            result = Spree::Otp::Verify.call(
              store: current_store,
              identifier: identifier,
              code: code,
              email_code: params[:email_code],
              accept_marketing: params.key?(:accept_marketing) ? ActiveModel::Type::Boolean.new.cast(params[:accept_marketing]) : nil,
              request_env: request_env_for_token
            )

            if result.success?
              render json: {
                token: result.value[:token],
                refresh_token: result.value[:refresh_token],
                user: serialize_user(result.value[:user])
              }, status: :ok
            else
              status_code = case result.value
                            when :max_attempts_exceeded then :too_many_requests
                            when :invalid_identifier then :unprocessable_entity
                            else :unauthorized
                            end

              render_error(
                code: result.value.to_s,
                message: result.error.to_s,
                status: status_code
              )
            end
          end

          # POST /api/v3/store/otp/request
          def request_otp
            identifier = params[:identifier]
            if identifier.blank?
              return render_error(
                code: 'missing_parameter',
                message: 'Identifier is required.',
                status: :unprocessable_entity
              )
            end

            result = Spree::Otp::Generate.call(
              store: current_store,
              identifier: identifier,
              mobile_number: params[:mobile_number],
              email: params[:email],
              request_env: request_env_for_token
            )

            if result.success?
              render json: { data: result.value }, status: :ok
            else
              status_code = case result.value
                            when :cooldown_active, :hourly_limit_exceeded then :too_many_requests
                            when :phone_already_registered, :email_linked_to_other_mobile then :conflict
                            else :unprocessable_entity
                            end

              message = result.error.value.is_a?(Hash) ? result.error.value[:message] : result.error.to_s
              retry_after = result.error.value.is_a?(Hash) ? result.error.value[:retry_after_seconds] : nil

              render_error(
                code: result.value.to_s,
                message: message,
                retry_after_seconds: retry_after,
                status: status_code
              )
            end
          end

          # POST /api/v3/store/otp/resend
          def resend
            identifier = params[:identifier]
            if identifier.blank?
              return render_error(
                code: 'missing_parameter',
                message: 'Identifier is required.',
                status: :unprocessable_entity
              )
            end

            result = Spree::Otp::Resend.call(
              store: current_store,
              identifier: identifier,
              request_env: request_env_for_token
            )

            if result.success?
              render json: { data: result.value }, status: :ok
            else
              status_code = case result.value
                            when :cooldown_active, :hourly_limit_exceeded then :too_many_requests
                            else :unprocessable_entity
                            end

              message = result.error.value.is_a?(Hash) ? result.error.value[:message] : result.error.to_s
              retry_after = result.error.value.is_a?(Hash) ? result.error.value[:retry_after_seconds] : nil

              render_error(
                code: result.value.to_s,
                message: message,
                retry_after_seconds: retry_after,
                status: status_code
              )
            end
          end

          # POST /api/v3/store/otp/fallback
          # "Send code by email instead" for the latest login attempt.
          def fallback
            identifier, = Spree::Otp::Identity.normalize_identifier(params[:identifier])
            if identifier.blank?
              return render_error(
                code: 'missing_parameter',
                message: 'Identifier is required.',
                status: :unprocessable_entity
              )
            end

            attempt = latest_login_attempt(identifier)
            unless attempt
              return render_error(
                code: 'invalid_identifier',
                message: 'Please request a new code.',
                status: :unprocessable_entity
              )
            end

            result = Spree::Otp::Fallback.call(store: current_store, attempt: attempt, reason: 'customer_requested', enforce_cooldown: true)

            if result.success?
              render json: {
                data: Spree::Otp::CodeSentPayload.build(attempt: result.value[:attempt], config: current_store.effective_otp_configuration)
              }, status: :ok
            else
              status_code = case result.value
                            when :email_fallback_disabled then :not_found
                            when :cooldown_active, :hourly_limit_exceeded then :too_many_requests
                            else :unprocessable_entity
                            end

              message = result.error.value.is_a?(Hash) ? result.error.value[:message] : result.error.to_s
              retry_after = result.error.value.is_a?(Hash) ? result.error.value[:retry_after_seconds] : nil

              render_error(code: result.value.to_s, message: message, retry_after_seconds: retry_after, status: status_code)
            end
          end

          # POST /api/v3/store/otp/status (body: identifier) — POST keeps the phone out of URLs/logs.
          # Lets the code screen notice an automatic switch to email (webhook path).
          def delivery_status
            identifier, = Spree::Otp::Identity.normalize_identifier(params[:identifier])
            attempt = identifier.present? ? latest_login_attempt(identifier) : nil
            unless attempt
              return render_error(code: 'not_found', message: 'No code in progress.', status: :not_found)
            end

            previous = Spree::OtpAttempt.where(store: current_store, identifier: identifier).login
                                        .where('created_at < ?', attempt.created_at)
                                        .order(created_at: :desc).first
            fell_back = attempt.channel == 'email' && previous&.delivery_status == 'fallback_sent'
            destination = Spree::Otp::Delivery.destination_for(attempt)

            render json: {
              data: {
                channel: attempt.channel,
                masked_target: Spree::Otp::Identity.mask(destination.to_s),
                delivery_status: fell_back ? 'fallback_sent' : attempt.delivery_status
              }
            }, status: :ok
          end

          # PATCH /api/v3/store/otp/customer/mobile
          def update_mobile
            if current_user.nil?
              return render_error(
                code: 'unauthorized',
                message: 'Authentication required.',
                status: :unauthorized
              )
            end

            mobile_number = params[:mobile_number]
            if mobile_number.blank?
              return render_error(
                code: 'missing_parameter',
                message: 'mobile_number is required.',
                status: :unprocessable_entity
              )
            end

            normalized = normalize_phone(mobile_number)
            unless normalized =~ /\A\+[1-9]\d{9,14}\z/
              return render_error(
                code: 'invalid_phone_format',
                message: 'Invalid phone number format.',
                status: :unprocessable_entity
              )
            end

            existing_user = Spree.user_class.where.not(id: current_user.id).find_by(mobile_number: normalized)
            if existing_user
              return render_error(
                code: 'mobile_already_registered',
                message: 'This mobile number is already linked to another account. Please sign in with that account.',
                status: :conflict
              )
            end

            current_user.confirm_mobile!(normalized)
            render json: { user: serialize_user(current_user) }, status: :ok
          end

          protected

          def serializer_params
            {
              store: current_store,
              locale: current_locale,
              currency: current_currency,
              user: current_user,
              includes: []
            }
          end

          private

          def render_error(code:, message:, status:, details: nil, retry_after_seconds: nil)
            error_response = {
              error: {
                code: code,
                message: message
              }
            }
            error_response[:error][:details] = details if details.present?
            error_response[:error][:retry_after_seconds] = retry_after_seconds if retry_after_seconds.present?

            render json: error_response, status: status
          end

          def serialize_user(user)
            # Serializers return string or symbol keys depending on the Spree
            # version; normalize so the extra fields replace rather than duplicate.
            serialized = user_serializer.new(user, params: serializer_params).to_h.stringify_keys
            serialized.merge(
              'id' => user.prefixed_id,
              'mobile_number' => user.mobile_number,
              'mobile_confirmed_at' => user.mobile_confirmed_at,
              'accepts_email_marketing' => user.accepts_email_marketing
            )
          end

          def user_serializer
            Spree.api.customer_serializer
          end

          def request_env_for_token
            {
              ip_address: request.remote_ip,
              user_agent: request.user_agent&.truncate(255)
            }
          end

          def normalize_phone(raw)
            Spree::Otp::Identity.normalize_phone(raw).to_s
          end

          # Newest unverified login attempt from the last 15 minutes.
          def latest_login_attempt(identifier)
            Spree::OtpAttempt.where(store: current_store, identifier: identifier, verified_at: nil).login
                             .where('created_at > ?', 15.minutes.ago)
                             .order(created_at: :desc).first
          end
        end
      end
    end
  end
end
