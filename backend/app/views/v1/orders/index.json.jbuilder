# frozen_string_literal: true

json.orders @orders, partial: "v1/orders/order", as: :order
json.meta do
  json.partial! "v1/shared/pagination", page_scope: @orders
end
