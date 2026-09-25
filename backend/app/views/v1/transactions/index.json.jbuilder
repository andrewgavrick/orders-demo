# frozen_string_literal: true

json.transactions @transactions do |journal|
  json.extract! journal, :id, :order_id, :kind, :reversal_of_id, :created_at, :posted_at
  json.entries journal.entries.sort_by(&:id) do |entry|
    json.extract! entry, :id, :account_id, :direction, :amount_minor, :created_at
    json.currency entry.account.currency
    json.actor_id entry.account.actor_id
  end
end
json.meta do
  json.partial! "v1/shared/pagination", page_scope: @transactions
end
