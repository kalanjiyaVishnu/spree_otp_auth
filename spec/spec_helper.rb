# frozen_string_literal: true

# Inside the host app these specs run through the host's rails_helper.
# Standalone (`bundle exec rake test_app && bundle exec rspec` here) they run
# against spec/dummy with spree_notification_providers installed.
host_helper = File.expand_path('../../../spec/rails_helper.rb', __dir__)
standalone = File.directory?(File.expand_path('dummy', __dir__))

if File.exist?(host_helper) && !standalone
  require host_helper
else
  ENV['RAILS_ENV'] ||= 'test'
  require File.expand_path('dummy/config/environment', __dir__)
  require 'rspec/rails'
  require 'spree_dev_tools/rspec/spec_helper'
  # Fixed keys so encrypted provider secrets work in the dummy app's tests.
  ActiveRecord::Encryption.configure(
    primary_key: 'test_primary_key_32_characters_12',
    deterministic_key: 'test_deterministic_key_32_char_1',
    key_derivation_salt: 'test_key_derivation_salt_32_ch_1'
  )

  # The dummy app has no Devise/Warden; specs written for the host's
  # `login_as(user, scope: :admin_user)` sign in by stubbing the admin
  # controllers' current user instead.
  module StandaloneAdminLogin
    def login_as(user, scope: nil) # rubocop:disable Lint/UnusedMethodArgument
      allow_any_instance_of(Spree::Admin::BaseController).to receive(:try_spree_current_user).and_return(user)
    end
  end
  unless defined?(Warden)
    module Warden
      def self.test_reset!; end
    end
  end
  RSpec.configure { |config| config.include StandaloneAdminLogin, type: :request }
  providers_support = Gem.loaded_specs['spree_notification_providers']&.full_gem_path
  Dir[File.join(providers_support, 'spec/support/**/*.rb')].each { |f| require f } if providers_support
end

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
end
