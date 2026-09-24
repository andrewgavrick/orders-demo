# frozen_string_literal: true

require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module OrdersApi
  class Application < Rails::Application
    config.load_defaults 8.1
    config.active_record.schema_format = :ruby
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true

    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_orders_demo_session", httponly: true, same_site: :strict,
      secure: Rails.env.production?
  end
end
