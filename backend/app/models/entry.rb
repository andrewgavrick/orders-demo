# frozen_string_literal: true

class Entry < ApplicationRecord
  belongs_to :account
  belongs_to :account_transaction, inverse_of: :entries

  enum :direction, { debit: "debit", credit: "credit" }, validate: true
  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validate :journal_is_draft, on: :create

  def readonly?
    persisted? || super
  end

  private

  def journal_is_draft
    if account_transaction&.posted_at?
      errors.add(:account_transaction, "has already been posted")
    end
  end
end
