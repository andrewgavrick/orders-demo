# frozen_string_literal: true

class ApiController < ApplicationController
  include Pagination

  before_action :require_json!, unless: -> { request.get? || request.head? }
  before_action :require_actor!

  rescue_from ActiveRecord::RecordNotFound do
    render_error(:not_found, "Resource not found", :not_found)
  end
  rescue_from ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError do
    render_error(:bad_request, "A valid JSON request body with the required parameters is expected", :bad_request)
  end
  rescue_from ActionController::BadRequest do |exception|
    render_error(:bad_request, exception.message, :bad_request)
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

  def set_own_actor
    @actor = Actor.kind_user.find(params[:actor_id] || params[:id])
    if @actor.id != current_actor.id
      render_error(:forbidden, "This actor's account is not available in the current session", :forbidden)
    end
  end

  def render_error(code, message, status = :unprocessable_entity)
    render json: { error: { code: code.to_s, message: message } }, status: status
  end
end
