# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rollback fault injection", type: :model do
  it "rolls back a journal and both real entry writes" do
    wallet = create(:account)
    asset = create(:account, purpose: "settlement", account_type: "asset")
    before_state = [ AccountTransaction.count, Entry.count ]
    expect do
      fail_after_financial_writes do
        ApplicationRecord.transaction(requires_new: true) do
          journal = AccountTransaction.create!(kind: "opening_balance")
          journal.entries.create!(account: asset, direction: "debit", amount_minor: 100)
          expect(journal.entries.count).to eq(1)
          journal.entries.create!(account: wallet, direction: "credit", amount_minor: 100)
          journal.post!
        end
      end
    end.to raise_error(FinancialFailure::InjectedFailure)
    expect([ AccountTransaction.count, Entry.count ]).to eq(before_state)
    expect(wallet.balance_minor).to eq(0)
  end
end
