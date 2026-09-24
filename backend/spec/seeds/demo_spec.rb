# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/demo")

RSpec.describe Demo::Seeds do
  before do
    stub_const("Demo::Seeds::NAMES", [ "Seed buyer", "Seed seller" ])
    stub_const("Demo::Seeds::OPENING_AMOUNT", 100_000)
  end

  it "creates funded wallets with balanced opening journals and no fake orders" do
    expect { described_class.call }.not_to change(Order, :count)
    wallets = Account.joins(:actor).where(actors: { name: described_class::NAMES }, purpose: "wallet")
    expect(wallets.count).to eq(2)
    wallets.each do |wallet|
      expect(wallet.balance_minor).to eq(100_000)
      journal = wallet.account_transactions.kind_opening_balance.sole
      expect(journal.order_id).to be_nil
      expect(journal.posted_at).to be_present
      expect(journal.entries.credit.sole.account).to eq(wallet)
      debit = journal.entries.debit.sole
      expect(debit.account.actor).to be_kind_system
      expect(debit.account).to be_asset
      expect(debit.amount_minor).to eq(100_000)
    end
  end

  it "does not duplicate actors, accounts or money when repeated after spending" do
    described_class.call
    buyer, seller = described_class::NAMES.map { |name| Actor.find_by!(name: name) }
    order = create(:order, buyer: buyer, seller: seller, amount_minor: 250)
    expect(Orders::Complete.call(order_id: order.id)).to be_success
    snapshot = [ Actor.count, Account.count, Entry.count, AccountTransaction.count,
      buyer.accounts.sole.balance_minor, seller.accounts.sole.balance_minor ]
    described_class.call
    expect([ Actor.count, Account.count, Entry.count, AccountTransaction.count,
      buyer.accounts.sole.balance_minor, seller.accounts.sole.balance_minor ]).to eq(snapshot)
  end

  it "rolls back the entire seed run on an interrupted financial write" do
    snapshot = [ Actor.count, Account.count, AccountTransaction.count, Entry.count ]
    expect { fail_after_financial_writes { described_class.call } }.to raise_error(FinancialFailure::InjectedFailure)
    expect([ Actor.count, Account.count, AccountTransaction.count, Entry.count ]).to eq(snapshot)
  end

  it "refuses to create demo money in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    expect { described_class.call }.to raise_error(/unavailable in production/)
  end
end
