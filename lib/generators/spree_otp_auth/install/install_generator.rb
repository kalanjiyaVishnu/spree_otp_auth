# frozen_string_literal: true

require 'rails/generators'

module SpreeOtpAuth
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc 'Install spree_otp_auth migrations and assets'

      class_option :migrate, type: :boolean, default: true, banner: 'Run migrations'

      # spree_otp_auth sends codes through spree_notification_providers, so its
      # tables are installed too (already-copied migrations are skipped).
      def add_migrations
        run 'bundle exec rake railties:install:migrations FROM=spree_notification_providers,spree_otp_auth'
      end

      def run_migrations
        if options[:migrate]
          run 'bundle exec rake db:migrate'
        else
          say_status :skipping, 'db:migrate, remember to run migrations manually'
        end
      end
    end
  end
end
