# frozen_string_literal: true

json.extract! account, :id, :actor_id, :account_type, :purpose, :currency
json.balance_minor account.balance_minor
