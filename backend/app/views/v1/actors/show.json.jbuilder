# frozen_string_literal: true

json.actor do
  json.partial! "v1/actors/actor", actor: @actor
end
json.accounts @accounts, partial: "v1/accounts/account", as: :account
