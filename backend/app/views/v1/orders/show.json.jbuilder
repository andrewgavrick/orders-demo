# frozen_string_literal: true

json.order do
  json.partial! "v1/orders/order", order: @order
end
