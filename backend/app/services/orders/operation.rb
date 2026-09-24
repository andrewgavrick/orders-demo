# frozen_string_literal: true

module Orders
  class Operation < BaseService
    class InvalidLedger < StandardError; end

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
      order.wallet_accounts.order(:id).lock.to_a
    end

    def post(order, kind:, postings:, original: nil)
      journal = AccountTransaction.create!(order: order, kind: kind, reversal_of: original)
      postings.each do |attributes|
        journal.entries.create!(attributes)
      end
      journal.post!
      order.reload
    end
  end
end
