# frozen_string_literal: true

json.actor do
  json.partial! "v1/actors/actor", actor: @actor
end
