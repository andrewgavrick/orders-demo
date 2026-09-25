# frozen_string_literal: true

module Orders
  class Create < BaseService
    def call(buyer:, attributes:)
      attributes = attributes.symbolize_keys.slice(:seller_id, :amount_minor, :currency)
      seller = Actor.kind_user.find(attributes.delete(:seller_id))
      return failure(:invalid_order, "Buyer must be a user") unless buyer.kind_user?
      return failure(:invalid_order, "Buyer and seller must differ") if buyer == seller

      order = buyer.purchases.build(attributes.merge(seller: seller))
      return failure(:validation_error, order.errors.full_messages.join(", ")) unless order.valid?
      unless order.wallet_accounts.count == 2
        return failure(:account_not_found, "Both actors need a wallet in the order currency")
      end

      order.save!
      Result.new(order: order, accounts: [], error: nil)
    end

    private

    def failure(code, message)
      Result.new(order: nil, accounts: [], error: Error.new(code: code, message: message))
    end
  end
end
