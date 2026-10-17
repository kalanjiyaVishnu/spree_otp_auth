# frozen_string_literal: true

require File.expand_path('../../../spec/rails_helper', __FILE__)

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
end
