# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'spree', '~> 5.5'
gem 'spree_admin', '~> 5.5'
gem 'spree_api', '~> 5.5'
# In this monorepo; after extraction use the released gem (the gemspec pins ~> 0.1).
providers_path = File.expand_path('../spree_notification_providers', __dir__)
gem 'spree_notification_providers', path: providers_path if File.directory?(providers_path)

group :development, :test do
  gem 'pg'
  gem 'propshaft'
  gem 'rails-controller-testing'
  gem 'spree_dev_tools'
end
