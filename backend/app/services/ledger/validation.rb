# frozen_string_literal: true

module Ledger
  class Validation
    def initialize(journal:, order:, entries:, accounts:)
      @journal, @order, @entries, @accounts = journal, order, entries, accounts
    end

    def validate!
      reject!(@journal.errors.full_messages.join(", ")) unless @journal.valid?
      reject!("A ledger transaction requires at least two entries") if @entries.size < 2
      reject!("A ledger transaction contains invalid entries") unless @entries.all?(&:valid?)
      validate_balance!
      validate_charge! if @journal.kind_charge?
      validate_reversal! if @journal.kind_reversal?
      validate_wallets!
    end

    private

    def reject!(message)
      raise InvalidTransaction, message
    end

    def validate_balance!
      totals = @entries.group_by { |entry| @accounts.fetch(entry.account_id).currency }
      unless totals.values.all? { |entries| entries.sum { |entry| entry.debit? ? entry.amount_minor : -entry.amount_minor }.zero? }
        reject!("Unbalanced ledger transaction by currency")
      end
    end

    def validate_charge!
      reject!("Only a created order can be charged") unless @order&.created?
      reject!("Buyer and seller must be distinct users") unless @order.buyer != @order.seller && @order.buyer.kind_user? && @order.seller.kind_user?
      valid = @entries.size == 2 && @entries.all? do |entry|
        account = @accounts.fetch(entry.account_id)
        actor_id = entry.debit? ? @order.buyer_id : @order.seller_id
        account.actor_id == actor_id && account.purpose == "wallet" && account.liability? &&
          account.currency == @order.currency && entry.amount_minor == @order.amount_minor
      end
      reject!("Charge must debit the buyer wallet and credit the seller wallet for the order amount and currency") unless valid
    end

    def validate_reversal!
      original = @journal.reversal_of
      unless @order&.successful? && original&.kind_charge? && original.posted_at? && original.order_id == @order.id
        reject!("Reversal must reference a posted charge of the same successful order")
      end
      expected = original.entries.map { |entry| [ entry.account_id, entry.amount_minor, entry.debit? ? "credit" : "debit" ] }.sort
      actual = @entries.map { |entry| [ entry.account_id, entry.amount_minor, entry.direction ] }.sort
      reject!("Reversal must exactly mirror the original entries") unless actual == expected
    end

    def validate_wallets!
      @entries.group_by(&:account_id).each do |account_id, entries|
        account = @accounts.fetch(account_id)
        next unless account.purpose == "wallet"

        delta = entries.sum { |entry| entry.credit? ? entry.amount_minor : -entry.amount_minor }
        reject!("Insufficient funds in wallet") if account.balance_minor + delta < 0
      end
    end
  end
end
