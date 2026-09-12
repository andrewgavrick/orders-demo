class AccountTransaction < ApplicationRecord
  belongs_to :order, optional: true
  belongs_to :reversal_of, class_name: "AccountTransaction", optional: true
  has_one :reversal, class_name: "AccountTransaction", foreign_key: :reversal_of_id,
    inverse_of: :reversal_of, dependent: :restrict_with_exception
  has_many :entries, inverse_of: :account_transaction, dependent: :restrict_with_exception
  has_many :accounts, through: :entries

  enum :kind, %w[charge reversal opening_balance].index_with(&:itself), prefix: true, validate: true
  validates :order, presence: true, unless: :kind_opening_balance?
  validates :order, absence: true, if: :kind_opening_balance?
  validates :reversal_of, absence: true, unless: :kind_reversal?
  validates :reversal_of, presence: true, if: :kind_reversal?

  # Call inside the same database transaction that creates all entries.
  # PostgreSQL validates the final journal at commit, including direct SQL writes.
  def post!
    update!(posted_at: Time.current)
  end

  def readonly?
    (persisted? && posted_at_in_database.present?) || super
  end
end
