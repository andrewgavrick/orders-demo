class ApiController < ApplicationController
  before_action :require_json!, unless: -> { request.get? || request.head? }
  before_action :require_actor!

  rescue_from ActiveRecord::RecordNotFound do
    render_error(:not_found, "Resource not found", :not_found)
  end
  rescue_from ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError do
    render_error(:bad_request, "A valid JSON request body with the required parameters is expected", :bad_request)
  end
  rescue_from ActiveRecord::RecordInvalid do |exception|
    render json: { error: { code: "validation_error", message: exception.record.errors.full_messages.join(", "), details: exception.record.errors.to_hash } }, status: :unprocessable_entity
  end

  private

  def current_actor
    @current_actor ||= Actor.kind_user.find_by(id: session[:actor_id])
  end

  def require_actor!
    render_error(:unauthorized, "Actor is not selected", :unauthorized) unless current_actor
  end

  def require_json!
    render_error(:unsupported_media_type, "Use Content-Type: application/json", :unsupported_media_type) unless request.media_type == "application/json"
  end

  def own_actor!
    actor = Actor.kind_user.find(params[:actor_id] || params[:id])
    if actor.id != current_actor.id
      render_error(:forbidden, "This actor's account is not available in the current session", :forbidden)
      return nil
    end
    actor
  end

  def render_error(code, message, status = :unprocessable_entity)
    render json: { error: { code: code.to_s, message: message } }, status: status
  end

  def paginate(scope)
    page = params.fetch(:page, "1").to_s
    size = params.fetch(:per_page, "50").to_s
    unless page.match?(/\A[1-9]\d{0,5}\z/) && size.match?(/\A[1-9]\d{0,2}\z/) && size.to_i <= 100
      render_error(:bad_request, "page must be 1..999999 and per_page must be 1..100", :bad_request)
      return nil
    end
    [ scope.limit(size.to_i).offset((page.to_i - 1) * size.to_i), { page: page.to_i, per_page: size.to_i, total: scope.count } ]
  end

  def actor_json(actor)
    actor.slice(:id, :name, :kind)
  end

  def order_json(order)
    order.slice(:id, :buyer_id, :seller_id, :amount_minor, :currency, :status, :created_at, :updated_at)
  end

  def account_json(account)
    account.slice(:id, :actor_id, :account_type, :purpose, :currency).merge(balance_minor: account.balance_minor.to_i)
  end

  def transaction_json(journal)
    journal.slice(:id, :order_id, :kind, :reversal_of_id, :created_at, :posted_at).merge(
      entries: journal.entries.sort_by(&:id).map do |entry|
        entry.slice(:id, :account_id, :direction, :amount_minor, :created_at).merge(
          currency: entry.account.currency, actor_id: entry.account.actor_id)
      end)
  end
end
