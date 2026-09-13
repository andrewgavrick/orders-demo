module Orders
  class Complete < Operation
    private

    def execute(order)
      return failure(:invalid_transition, "A cancelled order cannot be completed") if order.cancelled?

      accounts = lock_wallets(order)
      return success(order, accounts) if order.successful?
      return failure(:invalid_order, "Buyer and seller must differ") if order.buyer_id == order.seller_id

      buyer = accounts.find { |account| account.actor_id == order.buyer_id }
      seller = accounts.find { |account| account.actor_id == order.seller_id }
      return failure(:account_not_found, "Both actors need a wallet in the order currency") unless buyer && seller
      return failure(:insufficient_funds, "Insufficient funds in buyer wallet") if buyer.balance_minor < order.amount_minor

      post(order, kind: "charge", postings: [
        { account: buyer, direction: "debit", amount_minor: order.amount_minor },
        { account: seller, direction: "credit", amount_minor: order.amount_minor }
      ])
      success(order, accounts)
    end
  end
end
