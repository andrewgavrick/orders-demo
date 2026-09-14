class Actor < ApplicationRecord
  has_many :accounts, dependent: :restrict_with_exception
  has_many :purchases, class_name: "Order", foreign_key: :buyer_id, inverse_of: :buyer, dependent: :restrict_with_exception
  has_many :sales, class_name: "Order", foreign_key: :seller_id, inverse_of: :seller, dependent: :restrict_with_exception

  enum :kind, { system: "system", user: "user" }, prefix: true, validate: true
  validates :name, presence: true
end
