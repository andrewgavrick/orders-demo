# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ledger service concurrency", type: :model, concurrency: true do
  self.use_transactional_tests = false

  let(:buyer) { create(:actor, name: "Concurrent buyer") }
  let(:seller) { create(:actor, name: "Concurrent seller") }
  let(:wallet) { create(:account, actor: buyer) }
  let(:recipient) { create(:account, actor: seller) }
  let(:order) { create(:order, buyer: buyer, seller: seller, amount_minor: 80) }

  around do |example|
    raise "Dedicated ledger test database required" unless ApplicationRecord.connection_db_config.database == "orders_ledger_test"

    example.run
  end

  before do
    wallet
    recipient
    asset = buyer.accounts.create!(purpose: "settlement", currency: "USD", account_type: "asset")
    ApplicationRecord.transaction do
      journal = AccountTransaction.create!(kind: "opening_balance")
      journal.entries.create!(account: asset, direction: "debit", amount_minor: 100)
      journal.entries.create!(account: wallet, direction: "credit", amount_minor: 100)
      journal.post!
    end
  end

  after do
    # Remove only records created by this example, in foreign-key order.
    if buyer && seller
      ApplicationRecord.transaction do
        accounts = Account.where(actor_id: [ buyer.id, seller.id ])
        orders = Order.where(buyer_id: [ buyer.id, seller.id ])
        journals = AccountTransaction.where(id: Entry.where(account_id: accounts.select(:id)).select(:account_transaction_id)).pluck(:id)
        Entry.where(account_id: accounts.select(:id)).delete_all
        AccountTransaction.where(id: journals).delete_all
        orders.delete_all
        accounts.delete_all
        Actor.where(id: [ buyer.id, seller.id ]).delete_all
      end
    end
  end

  it "completes the same order once across separate connections" do
    expect(race(Orders::Complete, [ order.id, order.id ])).to all(be_success)
    expect(order.reload).to be_successful
    expect(order.account_transactions.kind_charge.count).to eq(1)
    expect([ wallet.balance_minor, recipient.balance_minor ]).to eq([ 20, 80 ])
  end

  it "allows only one of two orders to spend the same available funds" do
    orders = create_list(:order, 2, buyer: buyer, seller: seller, amount_minor: 80)
    results = race(Orders::Complete, orders.map(&:id))
    expect(results.count(&:success?)).to eq(1)
    expect(results.find(&:failure?).error.code).to eq(:insufficient_funds)
    expect(orders.map { |order| order.reload.status }).to contain_exactly("created", "successful")
    expect([ wallet.balance_minor, recipient.balance_minor ]).to eq([ 20, 80 ])
  end

  it "refunds the same order only once across separate connections" do
    Orders::Complete.call(order_id: order.id)
    expect(race(Orders::Cancel, [ order.id, order.id ])).to all(be_success)
    expect(order.reload).to be_cancelled
    expect(order.account_transactions.kind_reversal.count).to eq(1)
    expect([ wallet.balance_minor, recipient.balance_minor ]).to eq([ 100, 0 ])
  end

  it "serializes completion racing with cancellation without losing money" do
    dispatch = ->(order_id:) { order_id.first.call(order_id: order_id.last) }
    results = race(dispatch, [ [ Orders::Complete, order.id ], [ Orders::Cancel, order.id ] ])
    expect(results.select(&:failure?).map { |result| result.error.code }).to all(eq(:invalid_transition))
    expect(order.reload).to be_cancelled
    expect(order.account_transactions.count).to be_in([ 0, 2 ])
    expect([ wallet.balance_minor, recipient.balance_minor ]).to eq([ 100, 0 ])
  end
end
