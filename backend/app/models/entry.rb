class Entry < ApplicationRecord
  belongs_to :account
  belongs_to :account_transaction, inverse_of: :entries

  enum :direction, { debit: "debit", credit: "credit" }, validate: true
  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }

  def readonly?
    persisted? || super
  end
end
