# frozen_string_literal: true

module FinancialFailure
  class InjectedFailure < StandardError; end

  # Interrupt the real second entry INSERT, after PostgreSQL has executed it.
  def fail_after_financial_writes
    writes = 0
    owner = Thread.current
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      next unless Thread.current == owner
      next unless args.last.fetch(:sql).match?(/\A\s*INSERT\s+INTO\s+"?entries"?\b/i)

      writes += 1
      raise InjectedFailure, "Injected after both entry writes" if writes == 2
    end
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

RSpec.configure { |config| config.include FinancialFailure }
