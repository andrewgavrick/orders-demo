class V1::TransactionsController < ApiController
  def index
    actor = own_actor!
    return unless actor
    journal_ids = Entry.where(account_id: actor.accounts.select(:id)).select(:account_transaction_id)
    scope = AccountTransaction.where(id: journal_ids).where.not(posted_at: nil).order(created_at: :desc, id: :desc)
    result = paginate(scope)
    return unless result
    journals, meta = result
    render json: { transactions: journals.includes(entries: :account).map { |journal| transaction_json(journal) }, meta: meta }
  end
end
