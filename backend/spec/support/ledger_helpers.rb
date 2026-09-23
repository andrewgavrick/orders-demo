# frozen_string_literal: true

module LedgerHelpers
  def post_journal(kind:, entries:, order: nil, original: nil)
    ApplicationRecord.transaction(requires_new: true) do
      journal = AccountTransaction.create!(kind: kind, order: order, reversal_of: original)
      entries.each { |attributes| journal.entries.create!(attributes) }
      Ledger::Post.call(journal: journal)
    end
  end

  def charge_entries(amount = 250)
    [
      { account: buyer_wallet, direction: "debit", amount_minor: amount },
      { account: seller_wallet, direction: "credit", amount_minor: amount }
    ]
  end

  def charge(entries = charge_entries)
    post_journal(kind: "charge", order: order, entries: entries)
  end
end

RSpec.configure { |config| config.include LedgerHelpers, ledger_helpers: true }
