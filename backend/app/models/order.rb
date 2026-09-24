# frozen_string_literal: true

class Order < ApplicationRecord
  # Storage limit for positive amounts in a signed 64-bit bigint column.
  MAX_AMOUNT_MINOR = (2**63) - 1

  belongs_to :buyer, class_name: "Actor", inverse_of: :purchases
  belongs_to :seller, class_name: "Actor", inverse_of: :sales
  has_many :account_transactions, dependent: :restrict_with_exception

  enum :status, %w[created successful cancelled].index_with(&:itself), validate: true
  scope :visible_to, ->(actor) { where(buyer_id: actor.id).or(where(seller_id: actor.id)) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  validates :amount_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_AMOUNT_MINOR }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :protect_posted_attributes, on: :update

  def wallet_accounts
    Account.where(actor_id: [ buyer_id, seller_id ], purpose: "wallet", currency: currency)
  end

  private

  def protect_posted_attributes
    if %w[amount_minor currency buyer_id seller_id].any? { |attribute| will_save_change_to_attribute?(attribute) } &&
        account_transactions.posted.exists?
      errors.add(:base, "Posted order financial attributes cannot change")
    end
  end
end
