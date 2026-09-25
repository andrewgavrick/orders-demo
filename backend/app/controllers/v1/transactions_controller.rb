# frozen_string_literal: true

module V1
  class TransactionsController < ApiController
    before_action :set_own_actor

    def index
      @transactions = paginate(AccountTransaction.visible_to(@actor).posted.recent).includes(entries: :account)
      render :index
    end
  end
end
