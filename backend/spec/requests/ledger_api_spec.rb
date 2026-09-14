require "rails_helper"

RSpec.describe "Ledger HTTP API", type: :request do
  let(:buyer) { Actor.create!(name: "Buyer", kind: "user") }
  let(:seller) { Actor.create!(name: "Seller", kind: "user") }
  let(:outsider) { Actor.create!(name: "Outsider", kind: "user") }
  let(:wallet) { buyer.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability") }
  let(:recipient) { seller.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability") }
  let(:order) { Order.create!(buyer: buyer, seller: seller, amount_minor: 250, currency: "USD") }

  def select_actor(actor = buyer)
    post "/v1/session", params: { actor_id: actor.id }, as: :json
    expect(response).to have_http_status(:created)
  end

  def error(status, code)
    expect(response).to have_http_status(status)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body.fetch("error")).to include("code" => code, "message" => a_kind_of(String))
  end

  def fund
    wallet
    recipient
    asset = buyer.accounts.create!(purpose: "settlement", currency: "USD", account_type: "asset")
    # Test fixture only; public funding is deliberately not part of this API.
    journal = AccountTransaction.create!(kind: "opening_balance")
    journal.entries.create!(account: asset, direction: "debit", amount_minor: 1_000)
    journal.entries.create!(account: wallet, direction: "credit", amount_minor: 1_000)
    journal.post!
    ApplicationRecord.connection.execute("SET CONSTRAINTS ledger_commit IMMEDIATE")
    ApplicationRecord.connection.execute("SET CONSTRAINTS ledger_commit DEFERRED")
  end

  it "lists selectable users without exposing accounts or system actors" do
    buyer
    Actor.create!(name: "Platform", kind: "system")
    get "/v1/actors", as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("actors")).to eq(Actor.kind_user.order(:name, :id).map { |actor| actor.slice(:id, :name, :kind) })
  end

  it "persists the selected actor in a cookie and clears it on logout" do
    select_actor
    get "/v1/session", as: :json
    expect(response.parsed_body.dig("actor", "id")).to eq(buyer.id)
    delete "/v1/session", as: :json
    expect(response).to have_http_status(:no_content)
    get "/v1/session", as: :json
    error(401, "unauthorized")
  end

  it "rejects a system actor as the selected user" do
    actor = Actor.create!(name: "System", kind: "system")
    post "/v1/session", params: { actor_id: actor.id }, as: :json
    error(404, "not_found")
  end

  it "requires a session for orders" do
    get "/v1/actors/#{buyer.id}/orders", as: :json
    error(401, "unauthorized")
  end

  it "returns computed integer balances for the current actor only" do
    fund
    select_actor
    get "/v1/actors/#{buyer.id}", as: :json
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch("accounts").find { |item| item["id"] == wallet.id }
    expect(row).to include("actor_id" => buyer.id, "balance_minor" => 1_000, "currency" => "USD", "account_type" => "liability")
    expect(row.fetch("balance_minor")).to be_a(Integer)
    get "/v1/actors/#{seller.id}", as: :json
    error(403, "forbidden")
  end

  it "creates a buyer-owned order and ignores forged owner, status and posting fields" do
    wallet
    recipient
    select_actor
    journals_before = AccountTransaction.count
    expect do
      post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: seller.id, amount_minor: 250, currency: "USD", buyer_id: seller.id, status: "successful", posted_at: Time.current } }, as: :json
    end.to change(Order, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch("order")).to include("buyer_id" => buyer.id, "seller_id" => seller.id, "amount_minor" => 250, "status" => "created")
    expect(AccountTransaction.count).to eq(journals_before)
  end

  [ 0, -1, 1.5, "250", nil, 9_223_372_036_854_775_808 ].each do |amount|
    it "rejects invalid minor units #{amount.inspect}" do
      wallet
      recipient
      select_actor
      expect do
        post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: seller.id, amount_minor: amount, currency: "USD" } }, as: :json
      end.not_to change(Order, :count)
      error(422, "validation_error")
    end
  end

  it "rejects missing request bodies" do
    select_actor
    post "/v1/actors/#{buyer.id}/orders", params: {}, as: :json
    error(400, "bad_request")
  end

  it "rejects an unknown seller" do
    select_actor
    post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: -1, amount_minor: 250, currency: "USD" } }, as: :json
    error(404, "not_found")
  end

  it "rejects self purchases and missing matching wallets" do
    select_actor
    post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: buyer.id, amount_minor: 250, currency: "USD" } }, as: :json
    error(422, "invalid_order")
    post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: seller.id, amount_minor: 250, currency: "USD" } }, as: :json
    error(422, "account_not_found")
  end

  it "lists only participating orders newest first with stable pagination" do
    select_actor
    earlier = order
    later = Order.create!(buyer: seller, seller: buyer, amount_minor: 50, currency: "USD", created_at: earlier.created_at)
    Order.create!(buyer: seller, seller: outsider, amount_minor: 99, currency: "USD")
    get "/v1/actors/#{buyer.id}/orders", params: { per_page: 1 }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("orders").pluck("id")).to eq([ later.id ])
    expect(response.parsed_body.fetch("meta")).to include("page" => 1, "per_page" => 1, "total" => 2)
    get "/v1/actors/#{buyer.id}/orders", params: { page: 2, per_page: 1 }, headers: { "Accept" => "application/json" }
    expect(response.parsed_body.fetch("orders").pluck("id")).to eq([ earlier.id ])
  end

  it "returns an empty order collection and rejects invalid pagination" do
    select_actor
    get "/v1/actors/#{buyer.id}/orders", as: :json
    expect(response.parsed_body.fetch("orders")).to eq([])
    get "/v1/actors/#{buyer.id}/orders", params: { page: "oops" }, headers: { "Accept" => "application/json" }
    error(400, "bad_request")
  end

  it "allows seller reads but only buyer mutations" do
    order
    select_actor(seller)
    get "/v1/orders/#{order.id}", as: :json
    expect(response).to have_http_status(:ok)
    post "/v1/orders/#{order.id}/complete", as: :json
    error(403, "forbidden")
    post "/v1/orders/#{order.id}/cancel", as: :json
    error(403, "forbidden")
    expect(order.reload).to be_created
  end

  it "hides other actors' orders and journal" do
    order
    select_actor(outsider)
    get "/v1/orders/#{order.id}", as: :json
    error(404, "not_found")
    post "/v1/orders/#{order.id}/complete", as: :json
    error(404, "not_found")
    get "/v1/actors/#{buyer.id}/transactions", as: :json
    error(403, "forbidden")
  end

  it "runs create, complete, cancel, repeated cancel and reads the ledger through HTTP" do
    fund
    select_actor
    post "/v1/actors/#{buyer.id}/orders", params: { order: { seller_id: seller.id, amount_minor: 250, currency: "USD" } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig("order", "id")
    2.times do
      post "/v1/orders/#{id}/complete", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("order", "status")).to eq("successful")
      expect(response.parsed_body.fetch("accounts").find { |item| item["id"] == wallet.id }["balance_minor"]).to eq(750)
      expect(response.parsed_body.fetch("accounts").pluck("actor_id").uniq).to eq([ buyer.id ])
    end
    charge = Order.find(id).account_transactions.sole
    2.times do
      post "/v1/orders/#{id}/cancel", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("order", "status")).to eq("cancelled")
    end
    expect(wallet.balance_minor).to eq(1_000)
    expect(recipient.balance_minor).to eq(0)
    get "/v1/actors/#{buyer.id}/transactions", as: :json
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch("transactions").select { |item| item["order_id"] == id }
    expect(rows.size).to eq(2)
    reversal = rows.find { |item| item["kind"] == "reversal" }
    expect(reversal.fetch("reversal_of_id")).to eq(charge.id)
    expect(reversal.fetch("entries")).to contain_exactly(
      a_hash_including("account_id" => wallet.id, "direction" => "credit", "amount_minor" => 250, "currency" => "USD"),
      a_hash_including("account_id" => recipient.id, "direction" => "debit", "amount_minor" => 250, "currency" => "USD"))
  end

  it "returns insufficient_funds and keeps the order unchanged" do
    wallet
    recipient
    select_actor
    post "/v1/orders/#{order.id}/complete", as: :json
    error(422, "insufficient_funds")
    expect(order.reload).to be_created
    expect(order.account_transactions).to be_empty
  end

  it "returns insufficient_funds when a seller cannot refund" do
    fund
    Orders::Complete.call(order_id: order.id)
    spending = Order.create!(buyer: seller, seller: buyer, amount_minor: 100, currency: "USD")
    Orders::Complete.call(order_id: spending.id)
    select_actor
    post "/v1/orders/#{order.id}/cancel", as: :json
    error(422, "insufficient_funds")
    expect(order.reload).to be_successful
    expect(order.account_transactions.count).to eq(1)
  end

  it "cancels an unpaid order idempotently and rejects later completion" do
    select_actor
    2.times do
      post "/v1/orders/#{order.id}/cancel", as: :json
      expect(response).to have_http_status(:ok)
    end
    post "/v1/orders/#{order.id}/complete", as: :json
    error(422, "invalid_transition")
    expect(order.account_transactions).to be_empty
  end

  it "returns JSON 404 for unknown orders" do
    select_actor
    post "/v1/orders/-1/complete", as: :json
    error(404, "not_found")
  end

  it "uses the versioned session for order requests" do
    post "/v1/session", params: { actor_id: buyer.id }, as: :json
    expect(response).to have_http_status(:created)
    get "/v1/actors/#{buyer.id}/orders", as: :json
    expect(response).to have_http_status(:ok)
  end
end
