# Demo data is opt-in for existing databases and never runs in production.
Demo::Seeds.call unless Rails.env.production?
