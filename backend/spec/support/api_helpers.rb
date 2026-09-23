# frozen_string_literal: true

module ApiHelpers
  def select_actor(actor = buyer)
    post "/v1/session", params: { actor_id: actor.id }, as: :json
    expect(response).to have_http_status(:created)
  end

  def expect_api_error(status, code)
    expect(response).to have_http_status(status)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body.fetch("error")).to include("code" => code, "message" => a_kind_of(String))
  end

  def fund
    wallet
    recipient
    asset = buyer.accounts.create!(purpose: "settlement", currency: "USD", account_type: "asset")
    # Test fixture only; public funding is deliberately not part of this API.
    journal = AccountTransaction.create!(kind: "opening_balance")
    journal.entries.create!(account: asset, direction: "debit", amount_minor: 1_000)
    journal.entries.create!(account: wallet, direction: "credit", amount_minor: 1_000)
    journal.post!
  end
end

RSpec.configure { |config| config.include ApiHelpers, type: :request }
