require "rails_helper"

RSpec.describe "Order ledger consistency", type: :model do
  let(:order) { create(:order, amount_minor: 250) }
  let(:buyer) { create(:account, actor: order.buyer) }
  let(:seller) { create(:account, actor: order.seller) }

  def flush
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL DEFERRED")
  end

  def fund(account)
    asset = create(:account, purpose: "settlement", account_type: "asset")
    row = AccountTransaction.create!(kind: "opening_balance")
    row.entries.create!(account: asset, direction: "debit", amount_minor: 1_000)
    row.entries.create!(account: account, direction: "credit", amount_minor: 1_000)
    row.post!
  end

  def charge(debit: buyer, credit: seller, amount: 250)
    row = AccountTransaction.create!(order: order, kind: "charge")
    row.entries.create!(account: debit, direction: "debit", amount_minor: amount)
    row.entries.create!(account: credit, direction: "credit", amount_minor: amount)
    row.post!
    row
  end

  def rejects(message)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        yield
        flush
      end
    end.to raise_error(ActiveRecord::StatementInvalid, message) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
  end

  before do
    fund(buyer)
    seller
    flush
  end

  it "rejects successful status without payment through direct SQL" do
    rejects(/Order status/) { order.update_columns(status: "successful") }
    expect(order.reload).to be_created
  end

  it "rejects a posted payment without the corresponding status update" do
    rejects(/Order status/) { charge }
    expect(order.account_transactions.count).to eq(0)
    expect(buyer.balance_minor).to eq(1_000)
  end

  it "rejects cancelling or resetting a paid order without a reversal" do
    expect(Orders::Complete.call(order_id: order.id)).to be_success
    %w[cancelled created].each do |status|
      rejects(/Order status/) { order.update_columns(status: status) }
    end
    expect(order.reload).to be_successful
    expect(buyer.balance_minor).to eq(750)
  end

  it "rejects a reversal without cancelled status and reopening a refunded order" do
    Orders::Complete.call(order_id: order.id)
    rejects(/Order status/) do
      original = order.account_transactions.kind_charge.sole
      row = AccountTransaction.create!(order: order, kind: "reversal", reversal_of: original)
      original.entries.each do |entry|
        row.entries.create!(account_id: entry.account_id, amount_minor: entry.amount_minor,
          direction: entry.debit? ? "credit" : "debit")
      end
      row.post!
    end
    expect(Orders::Cancel.call(order_id: order.id)).to be_success
    %w[created successful].each do |status|
      rejects(/Order status/) { order.update_columns(status: status) }
    end
  end

  it "rejects a balanced payment for the wrong amount" do
    rejects(/Charge must/) do
      order.update_columns(status: "successful")
      charge(amount: 249)
    end
  end

  it "rejects the wrong participant, direction, currency and account purpose" do
    stranger = create(:account)
    fund(stranger)
    fund(seller)
    euro_buyer = create(:account, actor: order.buyer, currency: "EUR")
    euro_seller = create(:account, actor: order.seller, currency: "EUR")
    # Fund in EUR with a matching asset account.
    asset = create(:account, currency: "EUR", purpose: "settlement", account_type: "asset")
    row = AccountTransaction.create!(kind: "opening_balance")
    row.entries.create!(account: asset, direction: "debit", amount_minor: 1_000)
    row.entries.create!(account: euro_buyer, direction: "credit", amount_minor: 1_000)
    row.post!
    settlement = create(:account, actor: order.buyer, purpose: "settlement", account_type: "asset")
    flush
    [ [ stranger, seller ], [ buyer, stranger ], [ seller, buyer ],
      [ euro_buyer, euro_seller ], [ settlement, seller ] ].each do |debit, credit|
      rejects(/Charge must/) do
        order.update_columns(status: "successful")
        charge(debit: debit, credit: credit)
      end
    end
  end

  it "allows changing status before writing the matching entries in the same transaction" do
    order.update_columns(status: "successful")
    charge
    flush
    expect(buyer.balance_minor).to eq(750)
    expect(seller.balance_minor).to eq(250)
  end

  it "allows cancelling an unpaid order without entries" do
    order.update_columns(status: "cancelled")
    flush
    expect(order.account_transactions).to be_empty
  end

  it "rejects an inconsistent status at real COMMIT and rolls back the order" do
    config = ApplicationRecord.connection_db_config.configuration_hash
    connection = PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password])
    connection.exec("BEGIN")
    ids = %w[Buyer Seller].map do |name|
      connection.exec_params("INSERT INTO actors(kind, name, created_at, updated_at) VALUES ('user', $1, now(), now()) RETURNING id", [ name ])[0]["id"]
    end
    id = connection.exec_params("INSERT INTO orders(buyer_id, seller_id, amount_minor, currency, status, created_at, updated_at) VALUES ($1, $2, 250, 'USD', 'successful', now(), now()) RETURNING id", ids)[0]["id"]
    expect { connection.exec("COMMIT") }.to raise_error(PG::CheckViolation, /Order status/)
    expect(connection.exec_params("SELECT count(*) FROM orders WHERE id = $1", [ id ])[0]["count"]).to eq("0")
  ensure
    connection&.close
  end
end
