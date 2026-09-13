ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort("Specs must run in test") unless Rails.env.test?
require "rspec/rails"
require "factory_bot_rails"

ActiveRecord::Migration.maintain_test_schema!
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.include FactoryBot::Syntax::Methods
  config.order = :random
  Kernel.srand config.seed
end
