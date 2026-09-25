# frozen_string_literal: true

module V1
  class OrdersController < ApiController
    before_action :set_own_actor, only: %i[index create]
    before_action :set_order, only: %i[show complete cancel]
    before_action :require_buyer!, only: %i[complete cancel]

    def index
      @orders = paginate(Order.visible_to(@actor).recent)
      render :index
    end

    def show
      render :show
    end

    def create
      input = Orders::CreateForm.new(order_params)
      return render_error(:validation_error, input.errors.full_messages.join(", ")) unless input.valid?

      result = Orders::Create.call(buyer: @actor, attributes: input.attributes)
      return render_error(result.error.code, result.error.message) if result.failure?

      @order = result.order
      render :show, status: :created
    end

    def complete
      perform_operation(Orders::Complete)
    end

    def cancel
      perform_operation(Orders::Cancel)
    end

    private

    def order_params
      params.expect(order: [ :seller_id, :amount_minor, :currency ])
    end

    def set_order
      @order = Order.visible_to(current_actor).find(params[:id])
    end

    def require_buyer!
      render_error(:forbidden, "Only the buyer can change this order", :forbidden) unless @order.buyer_id == current_actor.id
    end

    def perform_operation(operation)
      result = operation.call(order_id: @order.id)
      if result.failure?
        status = result.error.code == :not_found ? :not_found : :unprocessable_entity
        return render_error(result.error.code, result.error.message, status)
      end

      @order = result.order
      @accounts = result.accounts.select { |account| account.actor_id == current_actor.id }
      render :operation
    end
  end
end
