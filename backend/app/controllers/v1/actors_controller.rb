# frozen_string_literal: true

module V1
  class ActorsController < ApiController
    skip_before_action :require_actor!, only: :index
    before_action :set_own_actor, only: :show

    def index
      @actors = paginate(Actor.kind_user.order(:name, :id))
      render :index
    end

    def show
      @accounts = @actor.accounts.order(:id)
      render :show
    end
  end
end
