class Order < ApplicationRecord
  belongs_to :buyer, class_name: "Actor", inverse_of: :purchases
  belongs_to :seller, class_name: "Actor", inverse_of: :sales
  has_many :account_transactions, dependent: :restrict_with_exception

  enum :status, %w[created successful cancelled].index_with(&:itself), validate: true
  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :protect_posted_attributes, on: :update

  private

  def protect_posted_attributes
    if %w[amount_minor currency buyer_id seller_id].any? { |attribute| will_save_change_to_attribute?(attribute) } &&
        account_transactions.where.not(posted_at: nil).exists?
      errors.add(:base, "Posted order financial attributes cannot change")
    end
  end
end
