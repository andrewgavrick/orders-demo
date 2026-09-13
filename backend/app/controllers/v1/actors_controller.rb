class V1::ActorsController < ApiController
  skip_before_action :require_actor!, only: :index

  def index
    result = paginate(Actor.kind_user.order(:name, :id))
    return unless result
    actors, meta = result
    render json: { actors: actors.map { |actor| actor_json(actor) }, meta: meta }
  end

  def show
    actor = own_actor!
    return unless actor
    render json: { actor: actor_json(actor), accounts: actor.accounts.order(:id).map { |account| account_json(account) } }
  end
end
