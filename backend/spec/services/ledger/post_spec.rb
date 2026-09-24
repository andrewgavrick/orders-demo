# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ledger::Post, ledger_helpers: true do
  let(:order) { create(:order, amount_minor: 250) }
  let(:buyer_wallet) { create(:account, actor: order.buyer) }
  let(:seller_wallet) { create(:account, actor: order.seller) }
  let(:asset) { create(:account, purpose: "settlement", account_type: "asset") }

  before do
    buyer_wallet
    seller_wallet
    post_journal(kind: "opening_balance", entries: [
      { account: asset, direction: "debit", amount_minor: 250 },
      { account: buyer_wallet, direction: "credit", amount_minor: 250 }
    ])
  end

  it "posts balanced entries, changes order status and calculates both account types" do
    charge
    expect(order.reload).to be_successful
    expect([ asset.balance_minor, buyer_wallet.balance_minor, seller_wallet.balance_minor ]).to eq([ 250, 0, 250 ])
  end

  it "rejects an empty journal and rolls back the draft" do
    expect do
      post_journal(kind: "charge", order: order, entries: [])
    end.to raise_error(Ledger::InvalidTransaction, /at least two/)
    expect(order.account_transactions).to be_empty
  end

  it "rejects unbalanced entries without leaving any partial financial writes" do
    snapshot = [ AccountTransaction.count, Entry.count, buyer_wallet.balance_minor ]
    entries = charge_entries
    entries.last[:amount_minor] = 249
    expect { charge(entries) }.to raise_error(Ledger::InvalidTransaction, /Unbalanced/)
    expect([ AccountTransaction.count, Entry.count, buyer_wallet.balance_minor ]).to eq(snapshot)
    expect(order.reload).to be_created
  end

  it "does not balance different currencies against each other" do
    seller_wallet.update!(currency: "EUR")
    expect { charge }.to raise_error(Ledger::InvalidTransaction, /Unbalanced/)
  end

  it "rejects a balanced charge for the wrong amount or participant" do
    expect { charge(charge_entries(249)) }.to raise_error(Ledger::InvalidTransaction, /Charge must/)
    entries = charge_entries
    entries.last[:account] = create(:account)
    expect { charge(entries) }.to raise_error(Ledger::InvalidTransaction, /Charge must/)
  end

  it "rejects a balanced overdraft" do
    order.update!(amount_minor: 251)
    expect { charge(charge_entries(251)) }.to raise_error(Ledger::InvalidTransaction, /Insufficient/)
    expect(order.reload).to be_created
  end

  it "rejects charging a cancelled order" do
    Orders::Cancel.call(order_id: order.id)
    expect { charge }.to raise_error(Ledger::InvalidTransaction, /created order/)
  end

  it "posts only exact reversals of the same successful order" do
    original = charge
    entries = [
      { account: buyer_wallet, direction: "credit", amount_minor: 100 },
      { account: seller_wallet, direction: "debit", amount_minor: 100 }
    ]
    expect do
      post_journal(kind: "reversal", order: order, original: original, entries: entries)
    end.to raise_error(Ledger::InvalidTransaction, /exactly mirror/)
    entries.each { |entry| entry[:amount_minor] = 250 }
    post_journal(kind: "reversal", order: order, original: original, entries: entries)
    expect(order.reload).to be_cancelled
    expect([ buyer_wallet.balance_minor, seller_wallet.balance_minor ]).to eq([ 250, 0 ])
    expect(original.reload).to be_kind_charge
  end

  it "rejects a reversal of another order or a reversal of a reversal" do
    original = charge
    other = create(:order)
    entries = [
      { account: buyer_wallet, direction: "credit", amount_minor: 250 },
      { account: seller_wallet, direction: "debit", amount_minor: 250 }
    ]
    expect do
      post_journal(kind: "reversal", order: other, original: original, entries: entries)
    end.to raise_error(Ledger::InvalidTransaction, /same successful order/)
    reversal = post_journal(kind: "reversal", order: order, original: original, entries: entries)
    expect do
      post_journal(kind: "reversal", order: order, original: reversal, entries: charge_entries)
    end.to raise_error(Ledger::InvalidTransaction, /same successful order/)
  end

  it "is idempotent when an already posted journal is submitted again" do
    journal = charge
    expect { described_class.call(journal: journal) }.not_to change(Entry, :count)
    expect(buyer_wallet.balance_minor).to eq(0)
  end

  it "keeps draft entries out of balances until posting" do
    journal = AccountTransaction.create!(kind: "charge", order: order)
    charge_entries.each { |attributes| journal.entries.create!(attributes) }
    expect(seller_wallet.balance_minor).to eq(0)
    journal.post!
    expect(seller_wallet.balance_minor).to eq(250)
  end

  it "rejects appending entries through Active Record after posting" do
    journal = charge
    expect do
      journal.entries.create!(account: seller_wallet, amount_minor: 1, direction: "credit")
    end.to raise_error(ActiveRecord::RecordInvalid, /already been posted/)
  end

  it "protects accounts with history through Active Record" do
    expect(buyer_wallet.update(currency: "EUR")).to be(false)
    expect(buyer_wallet.errors[:base]).to include("Cannot reinterpret an account with ledger history")
  end

  it "leaves no custom PostgreSQL triggers or functions" do
    connection = ApplicationRecord.connection
    expect(connection.select_value("SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN ('orders'::regclass, 'entries'::regclass, 'accounts'::regclass, 'account_transactions'::regclass)").to_i).to eq(0)
    expect(connection.select_value("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'ledger_%'").to_i).to eq(0)
  end
end
