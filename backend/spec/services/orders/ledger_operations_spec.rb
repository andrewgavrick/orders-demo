# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ledger order operations", type: :model do
  let(:buyer) { Actor.create!(name: "Buyer", kind: "user") }
  let(:seller) { Actor.create!(name: "Seller", kind: "user") }
  let(:wallet) { buyer.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability") }
  let(:recipient) { seller.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability") }
  let(:order) { Order.create!(buyer: buyer, seller: seller, amount_minor: 80, currency: "USD") }

  before do
    wallet
    recipient
    order
    # Opening funds are a balanced journal, never a direct balance assignment.
    asset = buyer.accounts.create!(purpose: "settlement", currency: "USD", account_type: "asset")
    funding = AccountTransaction.create!(kind: "opening_balance")
    funding.entries.create!(account: asset, direction: "debit", amount_minor: 100)
    funding.entries.create!(account: wallet, direction: "credit", amount_minor: 100)
    funding.post!
  end

  it "completes and cancels idempotently with a separate exact reversal" do
    2.times { expect(Orders::Complete.call(order_id: order.id)).to be_success }
    expect(order.reload).to be_successful
    expect([ wallet.balance_minor, recipient.balance_minor ]).to eq([ 20, 80 ])
    charge = order.account_transactions.sole
    original = charge.entries.order(:id).map(&:attributes)
    2.times { expect(Orders::Cancel.call(order_id: order.id)).to be_success }
    expect(order.reload).to be_cancelled
    expect([ wallet.balance_minor, recipient.balance_minor ]).to eq([ 100, 0 ])
    expect(order.account_transactions.count).to eq(2)
    expect(order.account_transactions.kind_reversal.sole.reversal_of_id).to eq(charge.id)
    expect(charge.entries.reload.order(:id).map(&:attributes)).to eq(original)
  end

  it "returns insufficient_funds without writes" do
    order.update!(amount_minor: 101)
    result = Orders::Complete.call(order_id: order.id)
    expect(result).to be_failure
    expect(result.error.code).to eq(:insufficient_funds)
    expect(order.reload).to be_created
    expect(wallet.balance_minor).to eq(100)
    expect(order.account_transactions).to be_empty
  end

  it "allows exact spending down to zero" do
    order.update!(amount_minor: 100)
    expect(Orders::Complete.call(order_id: order.id)).to be_success
    expect(wallet.balance_minor).to eq(0)
  end

  it "cancels unpaid orders without financial writes and rejects completion afterwards" do
    2.times { expect(Orders::Cancel.call(order_id: order.id)).to be_success }
    expect(order.account_transactions).to be_empty
    expect(wallet.balance_minor).to eq(100)
    expect(Orders::Complete.call(order_id: order.id).error.code).to eq(:invalid_transition)
  end

  it "refuses reversal if the seller has spent the proceeds" do
    Orders::Complete.call(order_id: order.id)
    spending = Order.create!(buyer: seller, seller: buyer, amount_minor: 50, currency: "USD")
    expect(Orders::Complete.call(order_id: spending.id)).to be_success
    expect(Orders::Cancel.call(order_id: order.id).error.code).to eq(:insufficient_funds)
    expect(order.reload).to be_successful
    expect(recipient.balance_minor).to eq(30)
    expect(order.account_transactions.count).to eq(1)
  end

  [ Orders::Complete, Orders::Cancel ].each do |operation|
    it "rolls back #{operation} when writing the second entry fails" do
      Orders::Complete.call(order_id: order.id) if operation == Orders::Cancel
      before_state = [ order.reload.status, wallet.balance_minor, recipient.balance_minor, Entry.count, AccountTransaction.count ]
      expect do
        fail_after_financial_writes { operation.call(order_id: order.id) }
      end.to raise_error(FinancialFailure::InjectedFailure)
      expect([ order.reload.status, wallet.balance_minor, recipient.balance_minor, Entry.count, AccountTransaction.count ]).to eq(before_state)
    end

    it "returns not_found from #{operation}" do
      expect(operation.call(order_id: -1).error.code).to eq(:not_found)
    end

    it "rolls back financial writes when #{operation} fails after posting" do
      Orders::Complete.call(order_id: order.id) if operation == Orders::Cancel
      before_state = [ order.reload.status, wallet.balance_minor, recipient.balance_minor, Entry.count, AccountTransaction.count ]
      allow_any_instance_of(Order).to receive(:update!).and_wrap_original do |method, *args|
        method.call(*args)
        raise "Injected failure after journal posting"
      end
      expect { operation.call(order_id: order.id) }.to raise_error(/Injected failure/)
      expect([ order.reload.status, wallet.balance_minor, recipient.balance_minor, Entry.count, AccountTransaction.count ]).to eq(before_state)
    end
  end
end
