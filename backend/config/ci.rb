# frozen_string_literal: true

# Run using bin/ci inside the backend environment.
CI.run do
  step "Prepare test database", "env RAILS_ENV=test bundle exec rails db:prepare"
  step "RSpec", "bundle exec rspec"
  step "Style: Ruby", "bin/rubocop"
  step "Autoloading", "env RAILS_ENV=test bundle exec rails zeitwerk:check"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
end
