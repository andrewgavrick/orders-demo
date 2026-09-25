# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::Create do
  subject(:result) { described_class.call(buyer: buyer, attributes: attributes) }

  let(:buyer) { create(:actor) }
  let(:seller) { create(:actor) }
  let(:attributes) { { seller_id: seller.id, amount_minor: 250, currency: "USD" } }

  context "when both participants have matching wallets" do
    before do
      create(:account, actor: buyer)
      create(:account, actor: seller)
    end

    it { is_expected.to be_success }

    it "creates a buyer-owned unpaid order without any ledger records" do
      expect(result.order).to have_attributes(buyer_id: buyer.id, seller_id: seller.id, status: "created")
      expect(result.order.account_transactions).to be_empty
    end

    context "when ownership and status are supplied by the caller" do
      let(:attributes) { super().merge(buyer_id: seller.id, status: "successful") }

      it "ignores attributes outside the creation contract" do
        expect(result.order).to have_attributes(buyer_id: buyer.id, status: "created")
      end
    end
  end

  context "when buyer and seller are the same user" do
    let(:seller) { buyer }

    it { expect(result.error.code).to eq(:invalid_order) }
  end

  context "when the seller only has a wallet in another currency" do
    before do
      create(:account, actor: buyer)
      create(:account, actor: seller, currency: "EUR")
    end

    it { expect(result.error.code).to eq(:account_not_found) }
    it { expect { result }.not_to change(Order, :count) }
  end

  [ 0, -1, 1.5, Order::MAX_AMOUNT_MINOR + 1 ].each do |amount|
    context "when the amount is #{amount}" do
      let(:attributes) { super().merge(amount_minor: amount) }

      it { expect(result.error.code).to eq(:validation_error) }
    end
  end

  context "when the buyer is a system actor" do
    let(:buyer) { create(:actor, kind: "system") }

    it { expect(result.error.code).to eq(:invalid_order) }
  end

  context "when the seller is a system actor" do
    let(:seller) { create(:actor, kind: "system") }

    it { expect { result }.to raise_error(ActiveRecord::RecordNotFound) }
  end
end
