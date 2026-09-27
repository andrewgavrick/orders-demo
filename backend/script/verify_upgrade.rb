# frozen_string_literal: true

# Run with rails runner against an empty, disposable database.
database = ApplicationRecord.connection_db_config.database
raise "A disposable orders_boot_smoke_upgrade database is required" unless database.start_with?("orders_boot_smoke_upgrade")
raise "Upgrade verification requires an empty database" if ApplicationRecord.connection.table_exists?(:actors)

ActiveRecord::Migration.verbose = false
migrations = ActiveRecord::MigrationContext.new(Rails.root.join("db/migrate").to_s)
migrations.migrate(20260914045327)
require Rails.root.join("db/seeds/demo")
Demo::Seeds.call

buyer, seller = Demo::Seeds::NAMES.first(2).map { |name| Actor.find_by!(name: name) }
order = Orders::Create.call(buyer: buyer, attributes: { seller_id: seller.id, amount_minor: 250, currency: "USD" }).order
raise "Charge failed before upgrade" unless Orders::Complete.call(order_id: order.id).success?

models = [ Actor, Account, Order, AccountTransaction, Entry ]
snapshot = models.map { |model| model.order(:id).map(&:attributes) }
migrations.migrate
raise "Upgrade modified financial data" unless snapshot == models.map { |model| model.order(:id).map(&:attributes) }

triggers = ApplicationRecord.connection.select_value(<<~SQL).to_i
  SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
  AND tgrelid IN ('orders'::regclass, 'accounts'::regclass, 'entries'::regclass, 'account_transactions'::regclass)
SQL
raise "Custom triggers remain" unless triggers.zero?
raise "Refund failed after upgrade" unless Orders::Cancel.call(order_id: order.id).success?
raise "Incorrect restored balance" unless buyer.accounts.sole.balance_minor == Demo::Seeds::OPENING_AMOUNT
raise "Incorrect recipient balance" unless seller.accounts.sole.balance_minor == Demo::Seeds::OPENING_AMOUNT
puts "Upgrade verified: historical migrations, posted data preserved, triggers removed, refund succeeds"
