# frozen_string_literal: true

module Demo
  class Seeds
    NAMES = [ "James Sullivan", "Michael Wazowski", "Mary Gibbs", "Randall Boggs",
      "Ceila Mae", "Henry Waternoose", "George Sanderson" ].freeze
    OPENING_AMOUNT = 100_000_000

    def self.call
      raise "Demo seeds are unavailable in production" if Rails.env.production?

      ApplicationRecord.transaction do
        system = Actor.find_or_create_by!(name: "System", kind: "system")
        settlement = system.accounts.find_or_create_by!(purpose: "settlement", currency: "USD") do |account|
          account.account_type = "asset"
        end
        wallets = NAMES.map do |name|
          actor = Actor.find_or_create_by!(name: name, kind: "user")
          actor.accounts.find_or_create_by!(purpose: "wallet", currency: "USD") do |account|
            account.account_type = "liability"
          end
        end
        Account.where(id: [ settlement.id, *wallets.map(&:id) ]).order(:id).lock.load
        wallets.each do |wallet|
          next if wallet.account_transactions.posted.kind_opening_balance.exists?

          journal = AccountTransaction.create!(kind: "opening_balance")
          journal.entries.create!(account: settlement, direction: "debit", amount_minor: OPENING_AMOUNT)
          journal.entries.create!(account: wallet, direction: "credit", amount_minor: OPENING_AMOUNT)
          journal.post!
        end
      end
    end
  end
end
