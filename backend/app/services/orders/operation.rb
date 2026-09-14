module Orders
  class Operation
    class InvalidLedger < StandardError; end

    def self.call(order_id:)
      new.call(order_id: order_id)
    end

    def call(order_id:)
      ApplicationRecord.transaction(requires_new: true) do
        order = Order.lock.find_by(id: order_id)
        next failure(:not_found, "Order not found") unless order

        execute(order)
      end
    end

    private

    def success(order, accounts = [])
      Result.new(order: order, accounts: accounts.freeze, error: nil)
    end

    def failure(code, message)
      Result.new(order: nil, accounts: [].freeze, error: Error.new(code: code, message: message))
    end

    def lock_wallets(order)
      Account.where(actor_id: [ order.buyer_id, order.seller_id ], purpose: "wallet", currency: order.currency)
        .order(:id).lock.to_a
    end

    def post(order, kind:, postings:, original: nil)
      journal = AccountTransaction.create!(order: order, kind: kind, reversal_of: original)
      postings.each do |attributes|
        journal.entries.create!(attributes)
      end
      journal.post!
      order.update!(status: kind == "charge" ? "successful" : "cancelled")
      # Validate before returning even when the caller owns an outer transaction.
      ApplicationRecord.connection.execute("SET CONSTRAINTS ledger_commit, ledger_order_commit IMMEDIATE")
      ApplicationRecord.connection.execute("SET CONSTRAINTS ledger_commit, ledger_order_commit DEFERRED")
    end
  end
end
