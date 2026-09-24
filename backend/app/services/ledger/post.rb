# frozen_string_literal: true

module Ledger
  # The single posting boundary. Callers create drafts and entries inside a
  # transaction; this service locks, checks and posts them atomically.
  class Post < BaseService
    def call(journal:)
      ApplicationRecord.transaction(requires_new: true) do
        # Match order operations: order -> journal -> accounts in ascending id.
        order = Order.lock.find(journal.order_id) if journal.order_id
        journal.lock!
        next journal if journal.posted_at?

        entries = journal.entries.order(:id).to_a
        accounts = Account.where(id: entries.map(&:account_id)).order(:id).lock.index_by(&:id)
        Validation.new(journal: journal, order: order, entries: entries, accounts: accounts).validate!
        journal.update!(posted_at: Time.current)
        order&.update!(status: journal.kind_charge? ? "successful" : "cancelled")
        journal
      end
    end
  end
end
