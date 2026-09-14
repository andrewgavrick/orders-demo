require "rails_helper"

RSpec.describe "Order domain", type: :model do
  it "stores bigint minor units exactly" do
    order = create(:order, amount_minor: 5_000_000_001)
    expect(order.reload.amount_minor).to eq(5_000_000_001)
  end

  it "rejects fractional amounts before PostgreSQL can truncate them" do
    expect(build(:order, amount_minor: 100.5)).not_to be_valid
    expect(build(:entry, amount_minor: 100.5)).not_to be_valid
  end

  it "allows one wallet per actor and currency and requires liability wallets" do
    wallet = create(:account)
    expect(build(:account, actor: wallet.actor)).not_to be_valid
    expect(build(:account, actor: wallet.actor, currency: "EUR")).to be_valid
    expect(build(:account, account_type: "asset")).not_to be_valid
  end

  it "requires orders for payments but forbids them on opening balances" do
    expect(build(:account_transaction, order: nil)).not_to be_valid
    expect(build(:account_transaction, kind: "opening_balance", order: nil)).to be_valid
    expect(build(:account_transaction, kind: "opening_balance")).not_to be_valid
  end

  it "protects posted journals and entries through Active Record" do
    wallet = create(:account)
    asset = create(:account, purpose: "settlement", account_type: "asset")
    journal = AccountTransaction.create!(kind: "opening_balance")
    journal.entries.create!(account: asset, direction: "debit", amount_minor: 100)
    entry = journal.entries.create!(account: wallet, direction: "credit", amount_minor: 100)
    journal.post!
    expect { journal.update!(created_at: 1.day.ago) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { journal.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect { entry.update!(amount_minor: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { entry.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
