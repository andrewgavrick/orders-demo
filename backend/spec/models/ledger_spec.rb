require "rails_helper"

RSpec.describe "Posted double-entry ledger", type: :model do
  let(:buyer) { Actor.create!(name: "Buyer", kind: "user") }
  let(:seller) { Actor.create!(name: "Seller", kind: "user") }
  let(:debit_account) { buyer.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability") }
  let(:credit_account) { seller.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability") }
  let(:order) { Order.create!(buyer: buyer, seller: seller, amount_minor: 250, currency: "USD") }

  before do
    debit_account
    credit_account
    order
    @asset = create(:account, purpose: "settlement", account_type: "asset")
    funding = AccountTransaction.create!(kind: "opening_balance")
    funding.entries.create!(account: @asset, direction: "debit", amount_minor: 250)
    funding.entries.create!(account: debit_account, direction: "credit", amount_minor: 250)
    funding.post!
    flush_constraints
  end

  def flush_constraints
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL DEFERRED")
  end

  def journal(amount: 250, credit: 250, posted: true, kind: "charge", original: nil)
    row = AccountTransaction.create!(order: order, kind: kind, reversal_of: original)
    row.entries.create!(account: debit_account, direction: kind == "charge" ? "debit" : "credit", amount_minor: amount)
    row.entries.create!(account: credit_account, direction: kind == "charge" ? "credit" : "debit", amount_minor: credit)
    row.post! if posted
    order.update!(status: kind == "charge" ? "successful" : "cancelled")
    row
  end

  def rejects(&block)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        block.call
        flush_constraints
      end
    end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
  end

  it "posts a balanced journal and computes debit-normal and credit-normal balances" do
    journal
    flush_constraints
    expect(@asset.balance_minor).to eq(250)
    expect(debit_account.balance_minor).to eq(0)
    expect(credit_account.balance_minor).to eq(250)
  end

  it "rejects unbalanced and unposted journals at the deferred boundary" do
    rejects { journal(credit: 249) }
    rejects { journal(posted: false) }
  end

  it "rejects an empty posted journal" do
    rejects { AccountTransaction.create!(order: order, kind: "charge", posted_at: Time.current) }
  end

  it "does not balance different currencies against each other" do
    credit_account.update!(currency: "EUR")
    rejects { journal }
  end

  it "rejects direct SQL updates, deletions and appends after posting" do
    row = journal
    flush_constraints
    rejects { AccountTransaction.where(id: row.id).update_all(posted_at: nil) }
    rejects { AccountTransaction.where(id: row.id).delete_all }
    rejects { row.entries.update_all(amount_minor: 1) }
    rejects { row.entries.delete_all }
    rejects { row.entries.create!(account: debit_account, direction: "debit", amount_minor: 1) }
  end

  it "preserves the meaning and owner of accounts with history" do
    journal
    flush_constraints
    rejects { debit_account.update_columns(currency: "EUR") }
    rejects { debit_account.update_columns(account_type: "asset") }
    rejects { debit_account.update_columns(actor_id: seller.id) }
    rejects { debit_account.update_columns(purpose: "other") }
  end

  it "posts a separate exact reversal without modifying the charge" do
    charge = journal
    flush_constraints
    before = charge.attributes
    reversal = journal(kind: "reversal", original: charge)
    flush_constraints
    expect(charge.reload.attributes).to eq(before)
    expect(reversal.reversal_of_id).to eq(charge.id)
    expect(debit_account.balance_minor).to eq(250)
    expect(credit_account.balance_minor).to eq(0)
  end

  it "rejects a balanced but incomplete reversal" do
    charge = journal
    flush_constraints
    rejects { journal(kind: "reversal", original: charge, amount: 100, credit: 100) }
  end

  it "rejects a wallet overdraft even when the journal is balanced" do
    order.update!(amount_minor: 251)
    rejects { journal(amount: 251, credit: 251) }
  end

  it "does not expose draft entries in the calculated balance" do
    row = journal(posted: false)
    expect(credit_account.balance_minor).to eq(0)
    row.post!
    flush_constraints
    expect(credit_account.balance_minor).to eq(250)
  end

  it "rejects a full reversal when the recipient has already spent the funds" do
    charge = journal
    flush_constraints
    spending_order = Order.create!(buyer: seller, seller: buyer, amount_minor: 200, currency: "USD")
    spending = AccountTransaction.create!(order: spending_order, kind: "charge")
    spending.entries.create!(account: credit_account, direction: "debit", amount_minor: 200)
    spending.entries.create!(account: debit_account, direction: "credit", amount_minor: 200)
    spending.post!
    spending_order.update!(status: "successful")
    flush_constraints
    rejects { journal(kind: "reversal", original: charge) }
    expect(credit_account.balance_minor).to eq(50)
    expect(charge.reload.reversal).to be_nil
  end

  it "rejects reversal of a reversal" do
    charge = journal
    flush_constraints
    reversal = journal(kind: "reversal", original: charge)
    flush_constraints
    rejects { journal(kind: "reversal", original: reversal) }
  end

  it "rejects an unbalanced real COMMIT on an independent connection" do
    config = ApplicationRecord.connection_db_config.configuration_hash
    connection = PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password])
    connection.exec("BEGIN")
    actor_id = connection.exec("INSERT INTO actors(kind, name, created_at, updated_at) VALUES ('system', 'Commit test', now(), now()) RETURNING id")[0]["id"]
    account_ids = %w[left right].map do |purpose|
      connection.exec_params("INSERT INTO accounts(actor_id, account_type, purpose, currency, created_at, updated_at) VALUES ($1, 'asset', $2, 'USD', now(), now()) RETURNING id", [ actor_id, purpose ])[0]["id"]
    end
    journal_id = connection.exec("INSERT INTO account_transactions(kind, created_at) VALUES ('opening_balance', now()) RETURNING id")[0]["id"]
    connection.exec_params("INSERT INTO entries(account_id, account_transaction_id, direction, amount_minor, created_at) VALUES ($1, $3, 'debit', 250, now()), ($2, $3, 'credit', 249, now())", [ *account_ids, journal_id ])
    connection.exec_params("UPDATE account_transactions SET posted_at = now() WHERE id = $1", [ journal_id ])
    expect { connection.exec("COMMIT") }.to raise_error(PG::CheckViolation, /Unbalanced/)
    expect(connection.exec_params("SELECT count(*) FROM actors WHERE id = $1", [ actor_id ])[0]["count"]).to eq("0")
  ensure
    connection&.close
  end
end
