module Orders
  class Cancel < Operation
    private

    def execute(order)
      return success(order, lock_wallets(order)) if order.cancelled?
      if order.created?
        order.update!(status: "cancelled")
        return success(order, lock_wallets(order))
      end

      original = order.account_transactions.kind_charge.find_by("posted_at IS NOT NULL")
      raise InvalidLedger, "Successful order has no posted charge" unless original
      entries = original.entries.order(:id).to_a
      accounts = Account.where(id: entries.map(&:account_id)).order(:id).lock.to_a
      # Check projected wallet balances, including multiple entries per account.
      accounts.select { |account| account.purpose == "wallet" }.each do |account|
        delta = entries.select { |entry| entry.account_id == account.id }
          .sum { |entry| entry.debit? ? entry.amount_minor : -entry.amount_minor }
        if account.balance_minor + delta < 0
          return failure(:insufficient_funds, "Insufficient funds to reverse the original payment")
        end
      end
      raise InvalidLedger, "Posted charge has no entries" if entries.empty?

      postings = entries.map do |entry|
        { account_id: entry.account_id, direction: entry.debit? ? "credit" : "debit", amount_minor: entry.amount_minor }
      end
      post(order, kind: "reversal", postings: postings, original: original)
      success(order, accounts)
    end
  end
end
