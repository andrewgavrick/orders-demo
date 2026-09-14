require "rails_helper"
require "timeout"

RSpec.describe "Ledger service concurrency", type: :model do
  self.use_transactional_tests = false

  before do
    raise "Dedicated ledger test database required" unless ApplicationRecord.connection_db_config.database == "orders_ledger_test"
    @buyer = Actor.create!(name: "Concurrent buyer", kind: "user")
    @seller = Actor.create!(name: "Concurrent seller", kind: "user")
    @wallet = @buyer.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability")
    @recipient = @seller.accounts.create!(purpose: "wallet", currency: "USD", account_type: "liability")
    asset = @buyer.accounts.create!(purpose: "settlement", currency: "USD", account_type: "asset")
    ApplicationRecord.transaction do
      journal = AccountTransaction.create!(kind: "opening_balance")
      journal.entries.create!(account: asset, direction: "debit", amount_minor: 100)
      journal.entries.create!(account: @wallet, direction: "credit", amount_minor: 100)
      journal.post!
    end
  end

  after do
    # Test-admin cleanup only: bypass immutable-history triggers locally,
    # delete only this example's actors and records, then restore on commit.
    if @buyer && @seller
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL session_replication_role = replica")
        accounts = Account.where(actor_id: [ @buyer.id, @seller.id ])
        orders = Order.where(buyer_id: [ @buyer.id, @seller.id ])
        journals = AccountTransaction.where(id: Entry.where(account_id: accounts.select(:id)).select(:account_transaction_id)).pluck(:id)
        Entry.where(account_id: accounts.select(:id)).delete_all
        AccountTransaction.where(id: journals).delete_all
        orders.delete_all
        accounts.delete_all
        Actor.where(id: [ @buyer.id, @seller.id ]).delete_all
      end
    end
  end

  def new_order(amount = 80)
    Order.create!(buyer: @buyer, seller: @seller, amount_minor: amount, currency: "USD")
  end

  def race(operation, ids)
    ready = Queue.new
    start = Queue.new
    done = Queue.new
    workers = []
    ApplicationRecord.connection_pool.with_connection do |coordinator|
      coordinator.transaction do
        @wallet.lock!
        workers = ids.map do |id|
          Thread.new do
            ApplicationRecord.connection_pool.with_connection do |connection|
              connection.execute("SET lock_timeout = '10s'")
              ready << connection.select_value("SELECT pg_backend_pid()")
              start.pop
              begin
                done << operation.call(order_id: id)
              rescue StandardError => error
                done << error
              ensure
                connection.execute("RESET lock_timeout")
              end
            end
          end
        end
        pids = Timeout.timeout(10) { ids.map { ready.pop } }
        expect(pids.uniq.size).to eq(ids.size)
        ids.size.times { start << true }
        Timeout.timeout(8) do
          loop do
            raise "A worker finished before the account lock was released" unless done.empty?
            coordinator.execute("SELECT pg_stat_clear_snapshot()")
            waiting = coordinator.select_value("SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{pids.map { |id| Integer(id) }.join(',')}) AND wait_event_type = 'Lock'").to_i
            break if waiting == ids.size
            sleep 0.02
          end
        end
      end
    end
    workers.each { |worker| raise "Worker timeout" unless worker.join(12) }
    workers.each(&:value)
    ids.map { done.pop }.tap do |results|
      results.each { |result| raise result if result.is_a?(Exception) }
    end
  ensure
    workers.each { |worker| worker.kill if worker.alive? }
    workers.each(&:join)
  end

  it "completes the same order once across separate connections" do
    order = new_order
    expect(race(Orders::Complete, [ order.id, order.id ])).to all(be_success)
    expect(order.reload).to be_successful
    expect(order.account_transactions.kind_charge.count).to eq(1)
    expect([ @wallet.balance_minor, @recipient.balance_minor ]).to eq([ 20, 80 ])
  end

  it "allows only one of two orders to spend the same available funds" do
    orders = [ new_order, new_order ]
    results = race(Orders::Complete, orders.map(&:id))
    expect(results.count(&:success?)).to eq(1)
    expect(results.find(&:failure?).error.code).to eq(:insufficient_funds)
    expect(orders.map { |order| order.reload.status }).to contain_exactly("created", "successful")
    expect([ @wallet.balance_minor, @recipient.balance_minor ]).to eq([ 20, 80 ])
  end

  it "refunds the same order only once across separate connections" do
    order = new_order
    Orders::Complete.call(order_id: order.id)
    expect(race(Orders::Cancel, [ order.id, order.id ])).to all(be_success)
    expect(order.reload).to be_cancelled
    expect(order.account_transactions.kind_reversal.count).to eq(1)
    expect([ @wallet.balance_minor, @recipient.balance_minor ]).to eq([ 100, 0 ])
  end
end
