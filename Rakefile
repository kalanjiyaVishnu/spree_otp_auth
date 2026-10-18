# frozen_string_literal: true

require 'bundler'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
require 'spree/testing_support/extension_rake'

RSpec::Core::RakeTask.new
task default: :spec

desc 'Generates spec/dummy, a Spree app with this extension installed, for the specs'
task :test_app do
  ENV['LIB_NAME'] = 'spree_otp_auth'
  Rake::Task['extension:test_app'].invoke
  # Admin screens render Spree's admin stylesheet: install its Tailwind entry
  # point and build it, as a fresh app would.
  Dir.chdir('spec/dummy') do
    system('bundle exec rails g spree:admin:install --force') || abort('Spree admin install failed')
    system('bundle exec rake spree:admin:tailwindcss:build') || abort('Building Spree admin CSS failed')
  end
end
