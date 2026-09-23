# frozen_string_literal: true

require "timeout"

module ConcurrencyHelpers
  def race(operation, ids)
    ready = Queue.new
    start = Queue.new
    done = Queue.new
    workers = []
    ApplicationRecord.connection_pool.with_connection do |coordinator|
      coordinator.transaction do
        wallet.lock!
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
end

RSpec.configure { |config| config.include ConcurrencyHelpers, concurrency: true }
