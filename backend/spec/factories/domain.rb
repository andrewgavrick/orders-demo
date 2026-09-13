FactoryBot.define do
  factory :actor do
    sequence(:name) { |n| "Actor #{n}" }
    kind { "user" }
  end

  factory :account do
    actor
    account_type { "liability" }
    purpose { "wallet" }
    currency { "USD" }
  end

  factory :order do
    association :buyer, factory: :actor
    association :seller, factory: :actor
    amount_minor { 10_000 }
    currency { "USD" }
    status { "created" }
  end

  # Draft journals must be populated and posted inside the caller's transaction.
  factory :account_transaction do
    order
    kind { "charge" }
  end

  factory :entry do
    account
    account_transaction
    direction { "credit" }
    amount_minor { 10_000 }
  end
end
