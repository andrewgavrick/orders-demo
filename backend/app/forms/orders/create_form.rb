# frozen_string_literal: true

module Orders
  # HTTP input contract: preserve JSON types before Active Record casts them.
  class CreateForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :seller_id
    attribute :amount_minor
    attribute :currency

    validate :json_types

    private

    def json_types
      errors.add(:seller_id, "must be a JSON integer") unless seller_id.is_a?(Integer)
      errors.add(:amount_minor, "must be a JSON integer") unless amount_minor.is_a?(Integer)
      errors.add(:currency, "must be a JSON string") unless currency.is_a?(String)
    end
  end
end
