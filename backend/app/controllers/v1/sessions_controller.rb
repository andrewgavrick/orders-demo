# frozen_string_literal: true

module V1
  class SessionsController < ApiController
    skip_before_action :require_actor!, only: :create

    def create
      actor_id = params.require(:actor_id)
      return render_error(:validation_error, "actor_id must be a JSON integer") unless actor_id.is_a?(Integer)

      @actor = Actor.kind_user.find(actor_id)
      reset_session
      session[:actor_id] = @actor.id
      render :show, status: :created
    end

    def show
      @actor = current_actor
      render :show
    end

    def destroy
      reset_session
      head :no_content
    end
  end
end
