require "rails_helper"

RSpec.describe "Financial database constraints", type: :model do
  let(:account) { create(:account) }
  let(:order) { create(:order) }

  def rejected(error = ActiveRecord::StatementInvalid, &block)
    expect { ApplicationRecord.transaction(requires_new: true, &block) }.to raise_error(error)
  end

  [ 0, -1 ].each do |amount|
    it "rejects order and entry amount #{amount} through direct SQL" do
      order
      account
      rejected { order.update_columns(amount_minor: amount) }
      rejected do
        journal = create(:account_transaction, order: order)
        Entry.insert_all!([ { account_id: account.id, account_transaction_id: journal.id,
          direction: "credit", amount_minor: amount, created_at: Time.current } ])
      end
    end
  end

  it "rejects unknown statuses and malformed currencies" do
    order
    account
    rejected { order.update_columns(status: "paid") }
    rejected { order.update_columns(currency: "usd") }
    rejected { account.update_columns(currency: "usd") }
    rejected { account.update_columns(account_type: "asset") }
  end

  it "rejects duplicate wallets through direct insertion" do
    row = account.attributes.except("id")
    rejected(ActiveRecord::RecordNotUnique) { Account.insert_all!([ row ]) }
  end

  it "rejects duplicate charges and reversals through direct insertion" do
    charge = create(:account_transaction, order: order)
    rejected(ActiveRecord::RecordNotUnique) { AccountTransaction.insert_all!([ charge.attributes.except("id") ]) }
    reversal = create(:account_transaction, order: order, kind: "reversal", reversal_of: charge)
    rejected(ActiveRecord::RecordNotUnique) { AccountTransaction.insert_all!([ reversal.attributes.except("id") ]) }
  end

  it "requires a reference for reversals and an order for payments" do
    order
    rejected { AccountTransaction.insert_all!([ { kind: "reversal", order_id: order.id, created_at: Time.current } ]) }
    rejected { AccountTransaction.insert_all!([ { kind: "charge", created_at: Time.current } ]) }
    rejected { AccountTransaction.insert_all!([ { kind: "opening_balance", order_id: order.id, created_at: Time.current } ]) }
  end

  it "rejects nonexistent actors, orders and accounts using foreign keys" do
    row = order.attributes.except("id")
    rejected(ActiveRecord::InvalidForeignKey) { Order.insert_all!([ row.merge("buyer_id" => -1) ]) }
    rejected(ActiveRecord::InvalidForeignKey) { Order.insert_all!([ row.merge("seller_id" => -1) ]) }
    rejected(ActiveRecord::InvalidForeignKey) do
      AccountTransaction.insert_all!([ { kind: "charge", order_id: -1, created_at: Time.current } ])
    end
    journal = create(:account_transaction, order: order)
    rejected(ActiveRecord::InvalidForeignKey) do
      Entry.insert_all!([ { account_id: -1, account_transaction_id: journal.id,
        direction: "credit", amount_minor: 1, created_at: Time.current } ])
    end
    account
    rejected(ActiveRecord::InvalidForeignKey) do
      Entry.insert_all!([ { account_id: account.id, account_transaction_id: -1,
        direction: "credit", amount_minor: 1, created_at: Time.current } ])
    end
  end

  it "protects referenced orders from deletion" do
    create(:account_transaction, order: order)
    rejected(ActiveRecord::InvalidForeignKey) { order.delete }
  end
end
