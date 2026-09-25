# frozen_string_literal: true

module Pagination
  extend ActiveSupport::Concern

  private

  def paginate(scope)
    page = params.fetch(:page, "1").to_s
    size = params.fetch(:per_page, "50").to_s
    unless page.match?(/\A[1-9]\d{0,5}\z/) && size.match?(/\A[1-9]\d{0,2}\z/) && size.to_i <= 100
      raise ActionController::BadRequest, "page must be 1..999999 and per_page must be 1..100"
    end

    scope.page(page.to_i).per(size.to_i)
  end
end
