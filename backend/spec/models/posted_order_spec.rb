# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Posted order protection", type: :model do
  let(:order) { create(:order, amount_minor: 250) }

  before do
    asset = create(:account, purpose: "settlement", account_type: "asset")
    wallet = create(:account, actor: order.buyer)
    journal = AccountTransaction.create!(kind: "opening_balance")
    journal.entries.create!(account: asset, direction: "debit", amount_minor: 250)
    journal.entries.create!(account: wallet, direction: "credit", amount_minor: 250)
    journal.post!
    create(:account, actor: order.seller)
    Orders::Complete.call(order_id: order.id)
  end

  it "rejects changing financial attributes through validations" do
    { amount_minor: 999, currency: "EUR", buyer_id: order.seller_id, seller_id: order.buyer_id }.each do |key, value|
      expect(order.reload.update(key => value)).to be(false)
      expect(order.errors[:base]).to include("Posted order financial attributes cannot change")
    end
  end

  it "preserves financial protection after cancellation and allows unchanged attributes" do
    Orders::Cancel.call(order_id: order.id)
    expect(order.update(amount_minor: 250)).to be(true)
    expect(order.update(amount_minor: 251)).to be(false)
  end

  it "allows editing an unpaid order" do
    unpaid = create(:order)
    expect(unpaid.update(amount_minor: 999, currency: "EUR")).to be(true)
  end
end
