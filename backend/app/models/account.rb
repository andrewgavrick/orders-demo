# frozen_string_literal: true

class Account < ApplicationRecord
  belongs_to :actor
  has_many :entries, dependent: :restrict_with_exception
  has_many :account_transactions, through: :entries

  enum :account_type, %w[asset liability equity revenue expense].index_with(&:itself), validate: true
  validates :purpose, presence: true, uniqueness: { scope: %i[actor_id currency] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :account_type, inclusion: { in: [ "liability" ] }, if: -> { purpose == "wallet" }
  validate :protect_history, on: :update

  def balance_minor
    debit_net = entries.joins(:account_transaction)
      .where.not(account_transactions: { posted_at: nil })
      .sum(Arel.sql("CASE WHEN direction = 'debit' THEN amount_minor ELSE -amount_minor END"))
    net = %w[asset expense].include?(account_type) ? debit_net : -debit_net
    net.to_i
  end

  private

  def protect_history
    if %w[actor_id currency account_type purpose].any? { |attribute| will_save_change_to_attribute?(attribute) } && entries.exists?
      errors.add(:base, "Cannot reinterpret an account with ledger history")
    end
  end
end
