# frozen_string_literal: true

# Demo data is opt-in for existing databases and never runs in production.
require_relative "seeds/demo"
Demo::Seeds.call unless Rails.env.production?
