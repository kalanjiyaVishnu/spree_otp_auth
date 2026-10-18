# frozen_string_literal: true

require_relative 'lib/spree_otp_auth/version'

Gem::Specification.new do |spec|
  spec.name        = 'spree_otp_auth'
  spec.version     = SpreeOtpAuth::VERSION
  spec.authors     = ['ONTODI']
  spec.summary     = 'Passwordless multi-channel OTP authentication and login-gated checkout for Spree Commerce'
  spec.description = <<~DESC.strip
    Provides mandatory login-gated checkout, passwordless customer authentication over WhatsApp,
    SMS or email with an automatic email backup, and store-scoped admin configuration. Codes are
    delivered through spree_notification_providers, so any provider and priority order works.
  DESC
  spec.license = 'BSD-3-Clause'

  spec.required_ruby_version = '>= 3.3'

  spec.files = Dir[
    '{app,config,db,lib}/**/*',
    'README.md',
    'CHANGELOG.md',
    'LICENSE',
    'spree_otp_auth.gemspec'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '>= 8.0'
  spec.add_dependency 'spree', '>= 5.5'
  spec.add_dependency 'spree_core', '>= 5.5'
  spec.add_dependency 'spree_api', '>= 5.5'
  spec.add_dependency 'spree_notification_providers', '~> 0.1'
  spec.add_dependency 'spree_admin', '>= 5.5'

  spec.homepage = 'https://github.com/ontodi/spree_otp_auth'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
end
