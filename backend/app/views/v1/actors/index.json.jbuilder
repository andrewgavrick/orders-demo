# frozen_string_literal: true

json.actors @actors, partial: "v1/actors/actor", as: :actor
json.meta do
  json.partial! "v1/shared/pagination", page_scope: @actors
end
