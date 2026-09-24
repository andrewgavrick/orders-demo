# frozen_string_literal: true

require Rails.root.join("db/seeds/demo")
# Run only against a disposable database created by db:prepare.
raise "A disposable orders_boot_smoke database is required" unless ApplicationRecord.connection_db_config.database.start_with?("orders_boot_smoke")

buyer, seller = Demo::Seeds::NAMES.first(2).map { |name| Actor.find_by!(name: name, kind: "user") }
wallet = buyer.accounts.find_by!(purpose: "wallet", currency: "USD")
recipient = seller.accounts.find_by!(purpose: "wallet", currency: "USD")
snapshot = [ Actor.count, Account.count, Entry.count, AccountTransaction.count, wallet.balance_minor, recipient.balance_minor ]
Demo::Seeds.call
raise "Seeds are not idempotent" unless snapshot == [ Actor.count, Account.count, Entry.count, AccountTransaction.count, wallet.balance_minor, recipient.balance_minor ]

client = ActionDispatch::Integration::Session.new(Rails.application)
client.host! "localhost"
client.post "/v1/session", params: { actor_id: buyer.id }, as: :json
raise "Session failed: #{client.response.status}" unless client.response.status == 201
client.post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: seller.id, amount_minor: 250, currency: "USD" } }, as: :json
raise "Create failed: #{client.response.body}" unless client.response.status == 201
id = client.response.parsed_body.fetch("order").fetch("id")
2.times do
  client.post "/v1/orders/#{id}/complete", as: :json
  raise "Complete failed: #{client.response.body}" unless client.response.status == 200
end
raise "Incorrect charge" unless wallet.balance_minor == snapshot[4] - 250 && recipient.balance_minor == snapshot[5] + 250
2.times do
  client.post "/v1/orders/#{id}/cancel", as: :json
  raise "Cancel failed: #{client.response.body}" unless client.response.status == 200
end
raise "Incorrect refund" unless wallet.balance_minor == snapshot[4] && recipient.balance_minor == snapshot[5]
raise "Duplicate payment" unless Order.find(id).account_transactions.count == 2
client.get "/v1/actors/#{buyer.id}/transactions", as: :json
raise "Journal failed" unless client.response.status == 200
raise "Opening balance absent" unless client.response.parsed_body.fetch("transactions").any? { |row| row["kind"] == "opening_balance" && row["order_id"].nil? }
puts "Demo verified: repeat seeds, session, create, complete twice, cancel twice, balances and journal"
