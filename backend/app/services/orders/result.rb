# frozen_string_literal: true

module Orders
  Result = Data.define(:order, :accounts, :error) do
    def success? = error.nil?
    def failure? = !success?
  end
end
