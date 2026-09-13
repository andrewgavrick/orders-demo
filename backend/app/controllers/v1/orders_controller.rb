class V1::OrdersController < ApiController
  def index
    actor = own_actor!
    return unless actor
    scope = Order.where(buyer_id: actor.id).or(Order.where(seller_id: actor.id)).order(created_at: :desc, id: :desc)
    result = paginate(scope)
    return unless result
    orders, meta = result
    render json: { orders: orders.map { |order| order_json(order) }, meta: meta }
  end

  def show
    render json: { order: order_json(visible_order) }
  end

  def create
    actor = own_actor!
    return unless actor
    body = params.require(:order)
    raise ActionController::ParameterMissing, :order unless body.is_a?(ActionController::Parameters)
    attributes = body.permit(:seller_id, :amount_minor, :currency)
    amount = attributes[:amount_minor]
    unless amount.is_a?(Integer) && amount.positive? && amount <= 9_223_372_036_854_775_807
      return render_error(:validation_error, "amount_minor must be a positive bigint JSON integer")
    end
    currency = attributes[:currency]
    unless currency.is_a?(String) && currency.match?(/\A[A-Z]{3}\z/)
      return render_error(:validation_error, "currency must contain three uppercase letters")
    end
    unless attributes[:seller_id].is_a?(Integer)
      return render_error(:validation_error, "seller_id must be a JSON integer")
    end
    seller = Actor.kind_user.find(attributes[:seller_id])
    return render_error(:invalid_order, "Buyer and seller must differ") if actor == seller
    wallets = Account.where(actor_id: [ actor.id, seller.id ], purpose: "wallet", currency: currency)
    return render_error(:account_not_found, "Both actors need a wallet in the order currency") unless wallets.count == 2
    order = Order.create!(buyer: actor, seller: seller, amount_minor: amount, currency: currency)
    render json: { order: order_json(order) }, status: :created
  end

  def complete
    perform_operation(Orders::Complete)
  end

  def cancel
    perform_operation(Orders::Cancel)
  end

  private

  def visible_order
    Order.where(buyer_id: current_actor.id).or(Order.where(seller_id: current_actor.id)).find(params[:id])
  end

  def perform_operation(operation)
    order = visible_order
    return render_error(:forbidden, "Only the buyer can change this order", :forbidden) unless order.buyer_id == current_actor.id
    result = operation.call(order_id: order.id)
    if result.failure?
      status = result.error.code == :not_found ? :not_found : :unprocessable_entity
      return render_error(result.error.code, result.error.message, status)
    end
    render json: { order: order_json(result.order), accounts: result.accounts.select { |account| account.actor_id == current_actor.id }.map { |account| account_json(account) } }
  end
end
